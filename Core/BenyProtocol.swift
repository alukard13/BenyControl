import Foundation

enum BenyProtocolError: LocalizedError, Equatable {
    case invalidPIN
    case invalidCurrent
    case malformedPacket
    case checksumMismatch
    case accessDenied
    case unsupportedPacket

    var errorDescription: String? {
        switch self {
        case .invalidPIN: return "El PIN debe tener exactamente seis dígitos."
        case .invalidCurrent: return "La corriente máxima debe estar entre 6 y 32 A."
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
}

struct BenyChargerStatus: Equatable {
    let activeFaults: [String]
}

enum BenyResponse: Equatable {
    case model(String)
    case values(BenyChargerValues)
    case status(BenyChargerStatus)
}

/// Port exact of the ASCII-hex UDP protocol in Jarauvi/beny_wifi.
enum BenyProtocol {
    private static let requestTemplate = "55aa10000b000[pin][requestType][checksum]"
    private static let commandTemplate = "55aa10000c000[pin]06[command][checksum]"
    private static let currentTemplate = "55aa10000d000[pin]6d00[current][checksum]"

    static func valuesRequest(pin: String) throws -> Data {
        try request(pin: pin, type: .values)
    }

    static func modelRequest(pin: String) throws -> Data {
        try request(pin: pin, type: .model)
    }

    static func statusRequest(pin: String) throws -> Data {
        try request(pin: pin, type: .status)
    }

    static func startRequest(pin: String) throws -> Data {
        try commandRequest(pin: pin, command: 1)
    }

    static func stopRequest(pin: String) throws -> Data {
        try commandRequest(pin: pin, command: 0)
    }

    static func setMaxCurrentRequest(pin: String, amps: Int) throws -> Data {
        guard (6...32).contains(amps) else { throw BenyProtocolError.invalidCurrent }
        return try build(template: currentTemplate, parameters: [
            "pin": try pinHex(pin),
            "current": String(format: "%02x", amps)
        ])
    }

    static func parse(_ data: Data) throws -> BenyResponse {
        guard let packet = String(data: data, encoding: .ascii), validateChecksum(packet) else {
            throw BenyProtocolError.checksumMismatch
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
            temperatureCelsius: rawTemperature - 100, maxCurrentAmps: maxCurrent
        )
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
