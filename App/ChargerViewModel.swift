import Foundation

@MainActor
final class ChargerViewModel: ObservableObject {
    @Published var ipAddress: String
    @Published var portText: String
    @Published var serialNumber: String
    @Published var pin: String
    @Published var dashboard = BenyDashboard()
    @Published var isConnected = false
    @Published var isWorking = false
    @Published var errorMessage: String?
    @Published var debugEnabled = false
    @Published var debugEvents: [BenyDebugEvent] = []

    private enum Key { static let ip = "charger.ip"; static let port = "charger.port"; static let serial = "charger.serial" }

    init(defaults: UserDefaults = .standard) {
        ipAddress = defaults.string(forKey: Key.ip) ?? BenyConnectionConfiguration.initial.ipAddress
        portText = defaults.string(forKey: Key.port) ?? "3333"
        serialNumber = defaults.string(forKey: Key.serial) ?? ""
        pin = (try? KeychainStore.loadPIN()) ?? ""
    }

    func save() {
        guard let configuration = validatedConfiguration() else { return }
        UserDefaults.standard.set(configuration.ipAddress, forKey: Key.ip)
        UserDefaults.standard.set(String(configuration.port), forKey: Key.port)
        UserDefaults.standard.set(configuration.serialNumber, forKey: Key.serial)
        do { try KeychainStore.savePIN(configuration.pin); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }

    func testConnection() { perform { service in
        self.dashboard.model = try await service.testConnection()
        self.isConnected = true
    }}

    func refresh() { perform { service in
        self.dashboard = try await service.refresh()
        self.isConnected = true
    }}

    func startCharging() { control { try await $0.startCharging() } }
    func stopCharging() { control { try await $0.stopCharging() } }
    func setCurrent(_ amps: Int) { control { try await $0.setMaxCurrent(amps) } }

    private func control(_ action: @escaping (BenyChargerService) async throws -> Void) {
        perform { service in
            try await action(service)
            self.dashboard = try await service.refresh()
            self.isConnected = true
        }
    }

    private func perform(_ action: @escaping (BenyChargerService) async throws -> Void) {
        guard let configuration = validatedConfiguration() else { return }
        save()
        isWorking = true; errorMessage = nil
        let traceIsEnabled = debugEnabled
        Task {
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
        }
    }

    private func validatedConfiguration() -> BenyConnectionConfiguration? {
        guard let port = UInt16(portText), !ipAddress.isEmpty, serialNumber.count == 9,
              serialNumber.allSatisfy(\.isNumber), pin.count == 6, pin.allSatisfy(\.isNumber) else {
            errorMessage = "IP, puerto, serie de 9 dígitos y PIN de 6 dígitos son obligatorios."
            return nil
        }
        return BenyConnectionConfiguration(ipAddress: ipAddress, port: port, serialNumber: serialNumber, pin: pin)
    }
}
