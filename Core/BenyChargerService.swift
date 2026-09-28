import Foundation

struct BenyConnectionConfiguration: Equatable {
    var ipAddress: String
    var port: UInt16
    var serialNumber: String
    var pin: String

    static let initial = BenyConnectionConfiguration(
        ipAddress: "192.168.8.127", port: 3333, serialNumber: "", pin: ""
    )
}

struct BenyDashboard: Equatable {
    var model = "BENY Charger"
    var values: BenyChargerValues?
    var status = BenyChargerStatus(activeFaults: [])
    var chargeStartMode: BenyChargeStartMode?
}

struct BenyDebugEvent: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let direction: String
    let hex: String
    let detail: String
}

actor BenyChargerService {
    private let configuration: BenyConnectionConfiguration
    private let client: BenyUDPClient
    private let trace: (@Sendable (BenyDebugEvent) -> Void)?

    init(configuration: BenyConnectionConfiguration, trace: (@Sendable (BenyDebugEvent) -> Void)? = nil) throws {
        self.configuration = configuration
        self.client = try BenyUDPClient(ipAddress: configuration.ipAddress, port: configuration.port)
        self.trace = trace
    }

    func testConnection() async throws -> String {
        let response = try await send(BenyProtocol.modelRequest(pin: configuration.pin))
        guard case .model(let model) = response else { throw BenyProtocolError.unsupportedPacket }
        return model
    }

    func refresh() async throws -> BenyDashboard {
        var dashboard = BenyDashboard()
        if case .model(let model) = try await send(BenyProtocol.modelRequest(pin: configuration.pin)) {
            dashboard.model = model
        }
        if case .values(let values) = try await send(BenyProtocol.valuesRequest(pin: configuration.pin)) {
            dashboard.values = values
        }
        if case .status(let status) = try await send(BenyProtocol.statusRequest(pin: configuration.pin)) {
            dashboard.status = status
        }
        if let response = try? await send(BenyProtocol.directSettingsReadRequest(pin: configuration.pin)),
           case .chargeStartMode(let mode) = response {
            dashboard.chargeStartMode = mode
        }
        return dashboard
    }

    func startCharging() async throws { try await sendControl(BenyProtocol.startRequest(pin: configuration.pin)) }
    func stopCharging() async throws { try await sendControl(BenyProtocol.stopRequest(pin: configuration.pin)) }
    func setChargeStartMode(_ mode: BenyChargeStartMode) async throws {
        try await sendControl(BenyProtocol.setChargeStartModeRequest(pin: configuration.pin, mode: mode))
    }
    func setMaxCurrent(_ amps: Int) async throws { try await sendControl(BenyProtocol.setMaxCurrentRequest(pin: configuration.pin, amps: amps)) }
    func setTimer(startHour: Int, startMinute: Int, endHour: Int?, endMinute: Int?) async throws {
        try await sendControl(BenyProtocol.setTimerRequest(pin: configuration.pin, startHour: startHour, startMinute: startMinute, endHour: endHour, endMinute: endMinute))
    }
    func resetTimer() async throws { try await sendControl(BenyProtocol.resetTimerRequest(pin: configuration.pin)) }
    func setWeeklySchedule(_ schedule: BenyWeeklySchedule) async throws {
        let start = schedule.startTime.split(separator: ":").compactMap { Int($0) }
        let end = schedule.endTime.split(separator: ":").compactMap { Int($0) }
        guard start.count == 2, end.count == 2 else { throw BenyProtocolError.invalidWeeklySchedule }
        try await sendControl(BenyProtocol.setWeeklyScheduleRequest(
            pin: configuration.pin,
            weekdays: schedule.weekdays,
            startHour: start[0], startMinute: start[1],
            endHour: end[0], endMinute: end[1]
        ))
    }
    func setMonthlyEnergyLimit(_ kilowattHours: Int) async throws {
        try await sendControl(BenyProtocol.setMonthlyEnergyLimitRequest(pin: configuration.pin, kilowattHours: kilowattHours))
    }
    func setSessionEnergyLimit(_ kilowattHours: Int) async throws {
        try await sendControl(BenyProtocol.setSessionEnergyLimitRequest(pin: configuration.pin, kilowattHours: kilowattHours))
    }
    func requestWeeklySchedule() async throws -> BenyWeeklySchedule {
        let packet = try BenyProtocol.directSettingsReadRequest(pin: configuration.pin)
        trace?(BenyDebugEvent(timestamp: .now, direction: "→", hex: BenyProtocol.redactedHex(packet), detail: "Horario semanal solicitado"))
        let reply = try await client.request(packet)
        trace?(BenyDebugEvent(timestamp: .now, direction: "←", hex: String(data: reply, encoding: .ascii) ?? "<no ASCII>", detail: "Horario semanal recibido"))
        return try BenyProtocol.parseWeeklySchedule(reply)
    }

    private func send(_ packet: Data) async throws -> BenyResponse {
        trace?(BenyDebugEvent(timestamp: .now, direction: "→", hex: BenyProtocol.redactedHex(packet), detail: "Enviado"))
        let reply = try await client.request(packet)
        trace?(BenyDebugEvent(timestamp: .now, direction: "←", hex: String(data: reply, encoding: .ascii) ?? "<no ASCII>", detail: "Recibido"))
        return try BenyProtocol.parse(reply)
    }

    private func sendControl(_ packet: Data) async throws {
        trace?(BenyDebugEvent(timestamp: .now, direction: "→", hex: BenyProtocol.redactedHex(packet), detail: "Control enviado"))
        let reply = try await client.request(packet)
        trace?(BenyDebugEvent(timestamp: .now, direction: "←", hex: String(data: reply, encoding: .ascii) ?? "<no ASCII>", detail: "Confirmación recibida"))
    }
}
