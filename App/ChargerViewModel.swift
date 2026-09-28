import Foundation

struct BenyChargerProfile: Identifiable, Equatable {
    var id: UUID
    var name: String
    var ipAddress: String
    var portText: String
    var serialNumber: String
    var pin: String

    static func empty(name: String = "") -> BenyChargerProfile {
        BenyChargerProfile(id: UUID(), name: name, ipAddress: "", portText: "3333", serialNumber: "", pin: "")
    }
}

private struct StoredBenyChargerProfile: Codable {
    let id: UUID
    let name: String
    let ipAddress: String
    let portText: String
    let serialNumber: String
}

@MainActor
final class ChargerViewModel: ObservableObject {
    @Published private(set) var chargers: [BenyChargerProfile]
    @Published private(set) var activeChargerID: UUID?
    @Published var dashboard = BenyDashboard()
    @Published var isConnected = false
    @Published var isWorking = false
    @Published private(set) var isCommandRunning = false
    @Published var errorMessage: String?
    @Published var debugEnabled = false
    @Published var debugEvents: [BenyDebugEvent] = []

    private enum Key {
        static let ip = "charger.ip"
        static let port = "charger.port"
        static let serial = "charger.serial"
        static let profiles = "chargers.profiles.v1"
        static let activeChargerID = "chargers.activeID"
    }

    private let defaults: UserDefaults
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let data = defaults.data(forKey: Key.profiles),
           let savedProfiles = try? JSONDecoder().decode([StoredBenyChargerProfile].self, from: data) {
            chargers = savedProfiles.map { profile in
                BenyChargerProfile(
                    id: profile.id,
                    name: profile.name,
                    ipAddress: profile.ipAddress,
                    portText: profile.portText,
                    serialNumber: profile.serialNumber,
                    pin: (try? KeychainStore.loadPIN(for: profile.id)) ?? ""
                )
            }
            let savedID = defaults.string(forKey: Key.activeChargerID).flatMap(UUID.init(uuidString:))
            activeChargerID = chargers.contains(where: { $0.id == savedID }) ? savedID : chargers.first?.id
        } else {
            let legacyPIN = (try? KeychainStore.loadPIN()) ?? ""
            let hasLegacySettings = defaults.object(forKey: Key.ip) != nil
                || defaults.object(forKey: Key.port) != nil
                || defaults.object(forKey: Key.serial) != nil
                || !legacyPIN.isEmpty

            if hasLegacySettings {
                let migrated = BenyChargerProfile(
                    id: UUID(),
                    name: "Mi cargador",
                    ipAddress: defaults.string(forKey: Key.ip) ?? BenyConnectionConfiguration.initial.ipAddress,
                    portText: defaults.string(forKey: Key.port) ?? "3333",
                    serialNumber: defaults.string(forKey: Key.serial) ?? "",
                    pin: legacyPIN
                )
                chargers = [migrated]
                activeChargerID = migrated.id
                if !legacyPIN.isEmpty { try? KeychainStore.savePIN(legacyPIN, for: migrated.id) }
                persistProfiles()
            } else {
                chargers = []
                activeChargerID = nil
            }
        }

        if let activeChargerID {
            defaults.set(activeChargerID.uuidString, forKey: Key.activeChargerID)
        }
    }

    var activeCharger: BenyChargerProfile? {
        chargers.first { $0.id == activeChargerID }
    }

    var activeChargerName: String {
        activeCharger?.name ?? "BenyControl"
    }

    func testConnection() {
        runExclusive { service in
            self.dashboard.model = try await service.testConnection()
            self.isConnected = true
        }
    }

    func refreshAutomatically(every interval: Duration = .seconds(3)) async {
        let clock = ContinuousClock()
        while !Task.isCancelled {
            let refreshStartedAt = clock.now
            if !isCommandRunning, hasValidConfiguration {
                await perform { service in
                    self.dashboard = try await service.refresh()
                    self.isConnected = true
                }
            }
            do {
                try await clock.sleep(until: refreshStartedAt.advanced(by: interval), tolerance: .milliseconds(100))
            } catch {
                return
            }
        }
    }

    func startCharging() { control { try await $0.startCharging() } }
    func stopCharging() { control { try await $0.stopCharging() } }
    func setCurrent(_ amps: Int) { control { try await $0.setMaxCurrent(amps) } }

    func saveCharger(_ draft: BenyChargerProfile) async -> String? {
        guard !isCommandRunning else { return "Espera a que termine la operación actual." }
        if let validationError = validationError(for: draft) { return validationError }

        isCommandRunning = true
        await waitUntilIdle()
        defer { isCommandRunning = false }

        var profile = draft
        profile.name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try KeychainStore.savePIN(profile.pin, for: profile.id)
        } catch {
            return error.localizedDescription
        }

        if let index = chargers.firstIndex(where: { $0.id == profile.id }) {
            chargers[index] = profile
        } else {
            chargers.append(profile)
        }
        if activeChargerID == nil { activeChargerID = profile.id }
        persistProfiles()
        if activeChargerID == profile.id { resetActiveChargerState() }
        return nil
    }

    func selectCharger(_ id: UUID) async {
        guard id != activeChargerID, chargers.contains(where: { $0.id == id }), !isCommandRunning else { return }
        isCommandRunning = true
        await waitUntilIdle()
        activeChargerID = id
        defaults.set(id.uuidString, forKey: Key.activeChargerID)
        resetActiveChargerState()
        isCommandRunning = false
    }

    func deleteCharger(_ id: UUID) async -> String? {
        guard chargers.contains(where: { $0.id == id }) else { return nil }
        guard !isCommandRunning else { return "Espera a que termine la operación actual." }

        isCommandRunning = true
        await waitUntilIdle()
        defer { isCommandRunning = false }

        do {
            try KeychainStore.deletePIN(for: id)
        } catch {
            return error.localizedDescription
        }

        chargers.removeAll { $0.id == id }
        if activeChargerID == id {
            activeChargerID = chargers.first?.id
            resetActiveChargerState()
        }
        persistProfiles()
        return nil
    }

    func validationError(for profile: BenyChargerProfile) -> String? {
        guard !profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Escribe un nombre para el cargador."
        }
        guard !profile.ipAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let port = UInt16(profile.portText), port > 0 else {
            return "Escribe una dirección IP y un puerto UDP válido."
        }
        guard profile.serialNumber.count == 9, profile.serialNumber.allSatisfy(\.isNumber) else {
            return "El número de serie debe tener 9 dígitos."
        }
        guard profile.pin.count == 6, profile.pin.allSatisfy(\.isNumber) else {
            return "El PIN debe tener 6 dígitos."
        }
        return nil
    }

    private func control(_ action: @escaping (BenyChargerService) async throws -> Void) {
        runExclusive { service in
            try await action(service)
            self.dashboard = try await service.refresh()
            self.isConnected = true
        }
    }

    private func runExclusive(_ action: @escaping (BenyChargerService) async throws -> Void) {
        guard !isCommandRunning else { return }
        isCommandRunning = true
        Task {
            await waitUntilIdle()
            await perform(action)
            isCommandRunning = false
        }
    }

    private func perform(_ action: @escaping (BenyChargerService) async throws -> Void) async {
        guard !isWorking else { return }
        guard let configuration = validatedConfiguration() else { return }
        isWorking = true
        errorMessage = nil
        let traceIsEnabled = debugEnabled
        do {
            let service = try BenyChargerService(configuration: configuration) { [weak self] event in
                guard traceIsEnabled else { return }
                Task { @MainActor in self?.debugEvents.insert(event, at: 0) }
            }
            try await action(service)
        } catch {
            errorMessage = error.localizedDescription
            isConnected = false
        }
        isWorking = false
        let waiters = idleWaiters
        idleWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    private func waitUntilIdle() async {
        guard isWorking else { return }
        await withCheckedContinuation { idleWaiters.append($0) }
    }

    private func validatedConfiguration() -> BenyConnectionConfiguration? {
        guard let profile = activeCharger,
              let port = UInt16(profile.portText), port > 0,
              !profile.ipAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              profile.serialNumber.count == 9, profile.serialNumber.allSatisfy(\.isNumber),
              profile.pin.count == 6, profile.pin.allSatisfy(\.isNumber) else {
            errorMessage = activeCharger == nil
                ? "Añade y configura un cargador en Ajustes."
                : "Revisa la IP, el puerto, la serie de 9 dígitos y el PIN de 6 dígitos en Ajustes."
            return nil
        }
        return BenyConnectionConfiguration(
            ipAddress: profile.ipAddress,
            port: port,
            serialNumber: profile.serialNumber,
            pin: profile.pin
        )
    }

    private var hasValidConfiguration: Bool {
        guard let profile = activeCharger,
              let port = UInt16(profile.portText), port > 0,
              !profile.ipAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              profile.serialNumber.count == 9, profile.serialNumber.allSatisfy(\.isNumber),
              profile.pin.count == 6, profile.pin.allSatisfy(\.isNumber) else {
            return false
        }
        return true
    }

    private func resetActiveChargerState() {
        dashboard = BenyDashboard()
        isConnected = false
        errorMessage = nil
    }

    private func persistProfiles() {
        let stored = chargers.map {
            StoredBenyChargerProfile(
                id: $0.id,
                name: $0.name,
                ipAddress: $0.ipAddress,
                portText: $0.portText,
                serialNumber: $0.serialNumber
            )
        }
        if let data = try? JSONEncoder().encode(stored) {
            defaults.set(data, forKey: Key.profiles)
        }
        if let activeChargerID {
            defaults.set(activeChargerID.uuidString, forKey: Key.activeChargerID)
        } else {
            defaults.removeObject(forKey: Key.activeChargerID)
        }
    }
}
