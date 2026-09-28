import Foundation

enum BenyProtocolError: LocalizedError, Equatable {
    case invalidPIN
    case invalidCurrent
    case invalidTime
    case invalidWeeklySchedule
    case invalidEnergyLimit
    case malformedPacket
    case checksumMismatch
    case accessDenied
    case unsupportedPacket

    var errorDescription: String? {
        switch self {
        case .invalidPIN: return "El PIN debe tener exactamente seis dígitos."
        case .invalidCurrent: return "La corriente máxima debe estar entre 6 y 32 A."
        case .invalidTime: return "La hora debe estar entre 00:00 y 23:59."
        case .invalidWeeklySchedule: return "Selecciona al menos un día y un intervalo horario válido."
        case .invalidEnergyLimit: return "El límite de energía está fuera del rango admitido."
        case .malformedPacket: return "El cargador devolvió un paquete con formato inválido."
        case .checksumMismatch: return "El checksum de la respuesta no es válido."
        case .accessDenied: return "El cargador rechazó el PIN."
        case .unsupportedPacket: return "El cargador devolvió un tipo de paquete no compatible."
        }
    }
}

enum BenyRequestType: UInt8 {
    case model = 4
    case status = 110
    case settings = 113
    case values = 112
}

enum BenyChargingState: Int, Codable, Equatable {
    case abnormal = 0, unplugged, standby, starting, unknown, waiting, charging

    var displayName: String {
        switch self {
        case .abnormal: return "Anómalo"
        case .unplugged: return "Sin vehículo"
        case .standby: return "En espera"
        case .starting: return "Iniciando"
        case .unknown: return "Desconocido"
        case .waiting: return "Esperando"
        case .charging: return "Cargando"
        }
    }
}

struct BenyChargerValues: Equatable {
    let state: BenyChargingState
    let currentAmps: Int
    let voltageVolts: Int
    let powerKilowatts: Double
    let totalEnergyKilowattHours: Double
    let temperatureCelsius: Int
    let maxCurrentAmps: Int
    let timerState: Int?
    let timerStartTime: String?
    let timerEndTime: String?
    let maxSessionConsumptionKilowattHours: Int?
}

struct BenyWeeklySchedule: Equatable {
    /// Monday through Sunday.
    let weekdays: [Bool]
    let startTime: String
    let endTime: String
}

enum BenyChargeStartMode: String, CaseIterable, Identifiable, Equatable {
    case connectAndStart
    case rfid
    case app
    case rfidAndApp

    var id: String { rawValue }
    var rfidEnabled: Bool { self == .rfid || self == .rfidAndApp }
    var appEnabled: Bool { self == .app || self == .rfidAndApp }

    var displayName: String {
        switch self {
        case .connectAndStart: return "Conectar e iniciar"
        case .rfid: return "Tarjeta RFID"
        case .app: return "Control desde la app"
        case .rfidAndApp: return "RFID y app"
        }
    }
}

struct BenyChargerStatus: Equatable {
    let activeFaults: [String]
}

enum BenyResponse: Equatable {
    case model(String)
    case values(BenyChargerValues)
    case status(BenyChargerStatus)
    case chargeStartMode(BenyChargeStartMode)
}

/// Port exact of the ASCII-hex UDP protocol in Jarauvi/beny_wifi.
enum BenyProtocol {
    private static let requestTemplate = "55aa10000b000[pin][requestType][checksum]"
    private static let commandTemplate = "55aa10000c000[pin]06[command][checksum]"
    private static let currentTemplate = "55aa10000d000[pin]6d00[current][checksum]"
    private static let timerTemplate = "55aa10001c000[pin]6900016008000[endTimerSet][startHour][startMinute]00[endHour][endMinute]0017153b[checksum]"
    private static let weeklyScheduleTemplate = "55aa100016000[pin]7519010e0f2725[weekdays][startHour][startMinute][endHour][endMinute][checksum]"
    private static let monthlyLimitTemplate = "55aa10000d000[pin]78[limit][checksum]"
    private static let sessionLimitTemplate = "55aa10000c000[pin]74[limit][checksum]"
    private static let resetTimerTemplate = "55aa10001c000[pin]690000000000000000000000000000171035[checksum]"
    private static let chargeStartModeTemplate = "55aa6a000d000[pin]6a[rfid][app][checksum]"
    private static let directSettingsReadTemplate = "55aa71000b000[pin]71[checksum]"

    static func valuesRequest(pin: String) throws -> Data {
        try request(pin: pin, type: .values)
    }

    static func modelRequest(pin: String) throws -> Data {
        try request(pin: pin, type: .model)
    }

    static func statusRequest(pin: String) throws -> Data {
        try request(pin: pin, type: .status)
    }

    static func weeklyScheduleRequest(pin: String) throws -> Data {
        try request(pin: pin, type: .settings)
    }

    static func startRequest(pin: String) throws -> Data {
        try commandRequest(pin: pin, command: 1)
    }

    static func stopRequest(pin: String) throws -> Data {
        try commandRequest(pin: pin, command: 0)
    }

    static func setChargeStartModeRequest(pin: String, mode: BenyChargeStartMode) throws -> Data {
        try build(template: chargeStartModeTemplate, parameters: [
            "pin": try pinHex(pin),
            "rfid": mode.rfidEnabled ? "01" : "00",
            "app": mode.appEnabled ? "01" : "00"
        ])
    }

    static func directSettingsReadRequest(pin: String) throws -> Data {
        try build(template: directSettingsReadTemplate, parameters: ["pin": try pinHex(pin)])
    }

    static func setMaxCurrentRequest(pin: String, amps: Int) throws -> Data {
        guard (6...32).contains(amps) else { throw BenyProtocolError.invalidCurrent }
        return try build(template: currentTemplate, parameters: [
            "pin": try pinHex(pin),
            "current": String(format: "%02x", amps)
        ])
    }

    static func setTimerRequest(pin: String, startHour: Int, startMinute: Int, endHour: Int? = nil, endMinute: Int? = nil) throws -> Data {
        guard validTime(startHour, startMinute) else { throw BenyProtocolError.invalidTime }
        if let endHour, let endMinute {
            guard validTime(endHour, endMinute) else { throw BenyProtocolError.invalidTime }
        } else if endHour != nil || endMinute != nil {
            throw BenyProtocolError.invalidTime
        }
        return try build(template: timerTemplate, parameters: [
            "pin": try pinHex(pin),
            "endTimerSet": endHour == nil ? "00000" : "11111",
            "startHour": String(format: "%02x", startHour),
            "startMinute": String(format: "%02x", startMinute),
            "endHour": String(format: "%02x", endHour ?? 0),
            "endMinute": String(format: "%02x", endMinute ?? 0)
        ])
    }

    static func resetTimerRequest(pin: String) throws -> Data {
        try build(template: resetTimerTemplate, parameters: ["pin": try pinHex(pin)])
    }

    static func setWeeklyScheduleRequest(pin: String, weekdays: [Bool], startHour: Int, startMinute: Int, endHour: Int, endMinute: Int) throws -> Data {
        guard weekdays.count == 7, weekdays.contains(true),
              validTime(startHour, startMinute), validTime(endHour, endMinute),
              startHour != endHour || startMinute != endMinute else {
            throw BenyProtocolError.invalidWeeklySchedule
        }
        let mask = weekdays.enumerated().reduce(into: 0) { result, item in
            let bit = (item.offset + 1) % 7 // Monday is bit 1; Sunday is bit 0.
            if item.element { result |= 1 << bit }
        }
        return try build(template: weeklyScheduleTemplate, parameters: [
            "pin": try pinHex(pin),
            "weekdays": String(format: "%02x", mask),
            "startHour": String(format: "%02x", startHour),
            "startMinute": String(format: "%02x", startMinute),
            "endHour": String(format: "%02x", endHour),
            "endMinute": String(format: "%02x", endMinute)
        ])
    }

    static func setMonthlyEnergyLimitRequest(pin: String, kilowattHours: Int) throws -> Data {
        guard (0...65_535).contains(kilowattHours) else { throw BenyProtocolError.invalidEnergyLimit }
        return try build(template: monthlyLimitTemplate, parameters: [
            "pin": try pinHex(pin), "limit": String(format: "%04x", kilowattHours)
        ])
    }

    static func setSessionEnergyLimitRequest(pin: String, kilowattHours: Int) throws -> Data {
        guard (0...255).contains(kilowattHours) else { throw BenyProtocolError.invalidEnergyLimit }
        return try build(template: sessionLimitTemplate, parameters: [
            "pin": try pinHex(pin), "limit": String(format: "%02x", kilowattHours)
        ])
    }

    static func parseWeeklySchedule(_ data: Data) throws -> BenyWeeklySchedule {
        guard let packet = String(data: data, encoding: .ascii), validateChecksum(packet),
              packet.count >= 42, hexInt(packet, 4, 6) == Int(BenyRequestType.settings.rawValue),
              let weekdayMask = hexInt(packet, 30, 32),
              let startHour = hexInt(packet, 32, 34), let startMinute = hexInt(packet, 34, 36),
              let endHour = hexInt(packet, 36, 38), let endMinute = hexInt(packet, 38, 40),
              validTime(startHour, startMinute), validTime(endHour, endMinute) else {
            throw BenyProtocolError.malformedPacket
        }
        let weekdays = (0..<7).map { index in
            let bit = (index + 1) % 7
            return weekdayMask & (1 << bit) != 0
        }
        return BenyWeeklySchedule(
            weekdays: weekdays,
            startTime: String(format: "%02d:%02d", startHour, startMinute),
            endTime: String(format: "%02d:%02d", endHour, endMinute)
        )
    }

    static func parse(_ data: Data) throws -> BenyResponse {
        guard let packet = String(data: data, encoding: .ascii), validateChecksum(packet) else {
            throw BenyProtocolError.checksumMismatch
        }
        if packet.hasPrefix("55aa7100") {
            return .chargeStartMode(try parseChargeStartModeSettings(packet))
        }
        guard packet.count >= 12, let identifier = hexInt(packet, 6, 10) else {
            throw BenyProtocolError.malformedPacket
        }

        if identifier == 8 { throw BenyProtocolError.accessDenied }
        switch identifier {
        case 30, 31: return .values(try parseSinglePhaseValues(packet))
        case 35, 36: throw BenyProtocolError.unsupportedPacket // MVP is Z74M / 1 phase.
        case 21: return .status(try parseStatus(packet))
        case 32: return .model(try parseModel(packet))
        default: throw BenyProtocolError.unsupportedPacket
        }
    }

    private static func parseChargeStartModeSettings(_ packet: String) throws -> BenyChargeStartMode {
        // In Z-Box's 0x71 settings response these adjacent flags are RFID and app control.
        // Captures of 0x6a writes confirm 00, 10, 01, and 11 combinations in that order.
        guard packet.count >= 18,
              let rfid = hexInt(packet, 12, 14), (0...1).contains(rfid),
              let app = hexInt(packet, 14, 16), (0...1).contains(app) else {
            throw BenyProtocolError.malformedPacket
        }
        switch (rfid, app) {
        case (0, 0): return .connectAndStart
        case (1, 0): return .rfid
        case (0, 1): return .app
        case (1, 1): return .rfidAndApp
        default: throw BenyProtocolError.malformedPacket
        }
    }

    static func redactedHex(_ data: Data) -> String {
        guard var value = String(data: data, encoding: .ascii) else { return "<non-ASCII>" }
        // The reference project notes that PIN occupies characters 13...18 in its UDP payloads.
        if value.count >= 18 {
            let start = value.index(value.startIndex, offsetBy: 13)
            let end = value.index(value.startIndex, offsetBy: 18)
            value.replaceSubrange(start..<end, with: "*****")
        }
        return value
    }

    static func packet(addingChecksumTo payload: String) throws -> Data {
        guard payload.count.isMultiple(of: 2), payload.allSatisfy({ $0.isHexDigit }) else {
            throw BenyProtocolError.malformedPacket
        }
        let checksum = checksum(of: payload)
        return Data((payload + String(format: "%02x", checksum)).utf8)
    }

    private static func request(pin: String, type: BenyRequestType) throws -> Data {
        try build(template: requestTemplate, parameters: [
            "pin": try pinHex(pin),
            "requestType": String(format: "%02x", type.rawValue)
        ])
    }

    private static func commandRequest(pin: String, command: UInt8) throws -> Data {
        try build(template: commandTemplate, parameters: [
            "pin": try pinHex(pin),
            "command": String(format: "%02x", command)
        ])
    }

    private static func build(template: String, parameters: [String: String]) throws -> Data {
        var payload = template
        for (key, value) in parameters { payload = payload.replacingOccurrences(of: "[\(key)]", with: value) }
        payload = payload.replacingOccurrences(of: "[checksum]", with: "")
        return try packet(addingChecksumTo: payload)
    }

    private static func pinHex(_ pin: String) throws -> String {
        guard pin.count == 6, pin.allSatisfy(\.isNumber), let value = Int(pin) else {
            throw BenyProtocolError.invalidPIN
        }
        // `beny_wifi` uses decimal PIN -> five hexadecimal characters, lowercase.
        return String(format: "%05x", value)
    }

    private static func checksum(of payload: String) -> UInt8 {
        stride(from: 0, to: payload.count, by: 2).reduce(0) { partial, offset in
            partial &+ UInt8(hexInt(payload, offset, offset + 2) ?? 0)
        }
    }

    private static func validateChecksum(_ packet: String) -> Bool {
        guard packet.count >= 4, packet.count.isMultiple(of: 2), packet.allSatisfy({ $0.isHexDigit }),
              let supplied = hexInt(packet, packet.count - 2, packet.count) else { return false }
        let payload = String(packet.dropLast(2))
        return Int(checksum(of: payload)) == supplied
    }

    private static func parseSinglePhaseValues(_ packet: String) throws -> BenyChargerValues {
        guard let current = hexInt(packet, 14, 16), let voltage = hexInt(packet, 18, 20),
              let power = hexInt(packet, 20, 24), let totalEnergy = hexInt(packet, 24, 28),
              let rawTemperature = hexInt(packet, 28, 30), let rawState = hexInt(packet, 30, 32),
              let state = BenyChargingState(rawValue: rawState), let maxCurrent = hexInt(packet, 46, 48) else {
            throw BenyProtocolError.malformedPacket
        }
        return BenyChargerValues(
            state: state, currentAmps: current, voltageVolts: voltage,
            powerKilowatts: Double(power) / 10, totalEnergyKilowattHours: Double(totalEnergy) / 10,
            temperatureCelsius: rawTemperature - 100, maxCurrentAmps: maxCurrent,
            timerState: hexInt(packet, 32, 34),
            timerStartTime: formattedTime(hour: hexInt(packet, 34, 36), minute: hexInt(packet, 36, 38)),
            timerEndTime: formattedTime(hour: hexInt(packet, 40, 42), minute: hexInt(packet, 42, 44)),
            maxSessionConsumptionKilowattHours: hexInt(packet, 48, 50)
        )
    }

    private static func validTime(_ hour: Int, _ minute: Int) -> Bool {
        (0...23).contains(hour) && (0...59).contains(minute)
    }

    private static func formattedTime(hour: Int?, minute: Int?) -> String? {
        guard let hour, let minute, validTime(hour, minute) else { return nil }
        return String(format: "%02d:%02d", hour, minute)
    }

    private static func parseStatus(_ packet: String) throws -> BenyChargerStatus {
        let faults: [(String, Int, Int)] = [
            ("Sobretensión", 12, 14), ("Subtensión", 14, 16), ("Sobrecarga", 16, 18),
            ("Temperatura alta", 18, 20), ("Tierra deficiente", 20, 22), ("Fuga", 22, 24),
            ("Señal CP", 24, 26), ("Parada de emergencia", 26, 28), ("Contactor", 38, 40)
        ]
        guard packet.count >= 40 else { throw BenyProtocolError.malformedPacket }
        return BenyChargerStatus(activeFaults: faults.compactMap { name, start, end in
            hexInt(packet, start, end) == 1 ? name : nil
        })
    }

    private static func parseModel(_ packet: String) throws -> String {
        guard let bytes = Data(hexadecimalString: packet), bytes.count > 8 else { throw BenyProtocolError.malformedPacket }
        let tail = bytes.dropFirst(8)
        guard let first = tail.firstIndex(where: { (32...126).contains($0) }) else {
            throw BenyProtocolError.malformedPacket
        }
        return String(bytes: tail[first...].prefix(while: { $0 != 0 && (32...126).contains($0) }), encoding: .ascii) ?? ""
    }

    private static func hexInt(_ value: String, _ start: Int, _ end: Int) -> Int? {
        guard start >= 0, end <= value.count, start < end else { return nil }
        let lower = value.index(value.startIndex, offsetBy: start)
        let upper = value.index(value.startIndex, offsetBy: end)
        return Int(value[lower..<upper], radix: 16)
    }
}

private extension Data {
    init?(hexadecimalString: String) {
        guard hexadecimalString.count.isMultiple(of: 2) else { return nil }
        var bytes = Data(); bytes.reserveCapacity(hexadecimalString.count / 2)
        var index = hexadecimalString.startIndex
        while index < hexadecimalString.endIndex {
            let next = hexadecimalString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexadecimalString[index..<next], radix: 16) else { return nil }
            bytes.append(byte); index = next
        }
        self = bytes
    }
}
