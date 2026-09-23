import XCTest
@testable import BenyControl

final class BenyProtocolTests: XCTestCase {
    func testValuesRequestMatchesReferencePacket() throws {
        let packet = try XCTUnwrap(String(data: BenyProtocol.valuesRequest(pin: "123456"), encoding: .ascii))
        XCTAssertEqual(packet, "55aa10000b0001e24070ad")
    }

    func testStartAndStopPacketsMatchReferenceTemplates() throws {
        XCTAssertEqual(String(data: try BenyProtocol.startRequest(pin: "123456"), encoding: .ascii), "55aa10000c0001e240060145")
        XCTAssertEqual(String(data: try BenyProtocol.stopRequest(pin: "123456"), encoding: .ascii), "55aa10000c0001e240060044")
    }

    func testSetCurrentPacketMatchesReferenceTemplate() throws {
        XCTAssertEqual(String(data: try BenyProtocol.setMaxCurrentRequest(pin: "123456", amps: 16), encoding: .ascii), "55aa10000d0001e2406d0010bc")
    }

    func testRejectsInvalidPINAndCurrent() {
        XCTAssertThrowsError(try BenyProtocol.valuesRequest(pin: "12345"))
        XCTAssertThrowsError(try BenyProtocol.setMaxCurrentRequest(pin: "123456", amps: 33))
    }

    func testParsesOnePhaseValuesWithReferenceConversions() throws {
        let payload = [
            "55aa", "10", "001e", "70", "00", "10", "00", "e6", "0016", "0014",
            "7d", "06", "00", "00", "00", "00", "00", "00", "00", "10", "00"
        ].joined()
        let packet = try BenyProtocol.packet(addingChecksumTo: payload)
        let result = try BenyProtocol.parse(packet)

        guard case .values(let values) = result else { return XCTFail("Expected values") }
        XCTAssertEqual(values.state, .charging)
        XCTAssertEqual(values.currentAmps, 16)
        XCTAssertEqual(values.voltageVolts, 230)
        XCTAssertEqual(values.powerKilowatts, 2.2, accuracy: 0.001)
        XCTAssertEqual(values.totalEnergyKilowattHours, 2.0, accuracy: 0.001)
        XCTAssertEqual(values.temperatureCelsius, 25)
        XCTAssertEqual(values.maxCurrentAmps, 16)
    }

    func testParsesStatusAndChecksumFailure() throws {
        let payload = ["55aa", "10", "0015", "6e", "00", "00", "01", "00", "00", "00", "00", "00", "00", "00", "00", "00", "00", "00", "00", "00"].joined()
        let packet = try BenyProtocol.packet(addingChecksumTo: payload)
        guard case .status(let status) = try BenyProtocol.parse(packet) else { return XCTFail("Expected status") }
        XCTAssertEqual(status.activeFaults, ["Sobrecarga"])
        XCTAssertThrowsError(try BenyProtocol.parse(Data("55aa10001e00".utf8)))
    }

    func testDiagnosticRedactsPIN() throws {
        let packet = try BenyProtocol.valuesRequest(pin: "123456")
        XCTAssertFalse(BenyProtocol.redactedHex(packet).contains("1e240"))
    }
}
