import Foundation
import Network

enum BenyUDPError: LocalizedError {
    case invalidEndpoint
    case connectionFailed(String)
    case timedOut
    case noResponse

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint: return "La IP o el puerto no son válidos."
        case .connectionFailed(let reason): return "No se pudo abrir UDP: \(reason)"
        case .timedOut: return "El cargador no respondió a tiempo."
        case .noResponse: return "No se recibió una respuesta UDP."
        }
    }
}

/// A serialized UDP request/response client. One request is always completed before another starts.
actor BenyUDPClient {
    private let host: NWEndpoint.Host
    private let port: NWEndpoint.Port
    private let queue = DispatchQueue(label: "com.benycontrol.udp")
    private var connection: NWConnection?

    init(ipAddress: String, port: UInt16) throws {
        guard let endpointPort = NWEndpoint.Port(rawValue: port), !ipAddress.isEmpty else {
            throw BenyUDPError.invalidEndpoint
        }
        self.host = NWEndpoint.Host(ipAddress)
        self.port = endpointPort
    }

    func connect(timeout: TimeInterval = 5) async throws {
        if connection != nil { return }
        let connection = NWConnection(host: host, port: port, using: .udp)
        self.connection = connection

        try await withCheckedThrowingContinuation { continuation in
            var didResolve = false
            connection.stateUpdateHandler = { [weak self] state in
                guard !didResolve else { return }
                switch state {
                case .ready:
                    didResolve = true
                    continuation.resume()
                case .failed(let error):
                    didResolve = true
                    Task { await self?.clear(connection) }
                    continuation.resume(throwing: BenyUDPError.connectionFailed(error.localizedDescription))
                case .cancelled:
                    didResolve = true
                    continuation.resume(throwing: BenyUDPError.connectionFailed("Conexión cancelada"))
                default:
                    break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) {
                guard !didResolve else { return }
                didResolve = true
                connection.cancel()
                Task { await self?.clear(connection) }
                continuation.resume(throwing: BenyUDPError.timedOut)
            }
        }
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
    }

    func request(_ packet: Data, timeout: TimeInterval = 5) async throws -> Data {
        try await connect(timeout: timeout)
        guard let connection else { throw BenyUDPError.connectionFailed("Sin conexión UDP") }

        return try await withCheckedThrowingContinuation { continuation in
            var didResolve = false
            func resolve(_ result: Result<Data, Error>) {
                guard !didResolve else { return }
                didResolve = true
                continuation.resume(with: result)
            }

            connection.receiveMessage { data, _, _, error in
                if let error { resolve(.failure(BenyUDPError.connectionFailed(error.localizedDescription))) }
                else if let data { resolve(.success(data)) }
                else { resolve(.failure(BenyUDPError.noResponse)) }
            }
            connection.send(content: packet, completion: .contentProcessed { error in
                if let error { resolve(.failure(BenyUDPError.connectionFailed(error.localizedDescription))) }
            })
            self.queue.asyncAfter(deadline: .now() + timeout) {
                resolve(.failure(BenyUDPError.timedOut))
            }
        }
    }

    private func clear(_ expected: NWConnection) {
        if connection === expected { connection = nil }
    }
}
