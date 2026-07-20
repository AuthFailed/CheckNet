import Foundation
import Network

/// A TLS connection we drive by hand: we choose the destination IP, the SNI, and
/// crucially the *segmentation* of what we send.
///
/// Censorship probes need that control. Sending 64 bytes as one segment and
/// sending the same 64 bytes as 32 two-byte segments are indistinguishable to a
/// normal networking API, but a packet-counting middlebox treats them very
/// differently — and that difference is the measurement.
final class TLSStream: @unchecked Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "networkkit.censorship.stream")

    /// - Parameters:
    ///   - ip: literal address, so DNS never enters the measurement
    ///   - serverName: SNI to advertise; may deliberately differ from the host
    ///     that owns `ip` — that mismatch is the whitelist probe
    init(ip: String, port: UInt16, serverName: String) throws {
        let tlsOptions = NWProtocolTLS.Options()
        let sec = tlsOptions.securityProtocolOptions
        sec_protocol_options_set_tls_server_name(sec, serverName)
        // We connect by IP and often with a deliberately mismatched SNI, so chain
        // validation would fail for reasons that have nothing to do with the
        // measurement. Accept whatever we get; we never send real data.
        sec_protocol_options_set_verify_block(sec, { _, _, complete in
            complete(true)
        }, queue)

        let tcpOptions = NWProtocolTCP.Options()
        // Without this, the OS coalesces our small writes and the segmentation
        // experiment silently becomes meaningless.
        tcpOptions.noDelay = true

        let params = NWParameters(tls: tlsOptions, tcp: tcpOptions)
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw NetworkError.protocolError("некорректный порт")
        }
        connection = NWConnection(host: NWEndpoint.Host(ip), port: nwPort, using: params)
    }

    /// Completes the TCP connect and TLS handshake, or throws.
    func open(timeout: TimeInterval) async throws {
        let gate = ContinuationGate<Void>()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                gate.arm(cont)
                connection.stateUpdateHandler = { [connection] state in
                    switch state {
                    case .ready:
                        gate.succeed(())
                    case .failed(let error):
                        connection.cancel()
                        gate.fail(error)
                    case .cancelled:
                        gate.fail(NetworkError.cancelled)
                    default:
                        break
                    }
                }
                connection.start(queue: queue)
                queue.asyncAfter(deadline: .now() + timeout) { [connection] in
                    if gate.failIfPending(NetworkError.timedOut) { connection.cancel() }
                }
            }
        } onCancel: {
            connection.cancel()
        }
    }

    /// Writes `bytes` as a single segment (subject to `noDelay`).
    func send(_ bytes: [UInt8]) async throws {
        let gate = ContinuationGate<Void>()
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            gate.arm(cont)
            connection.send(content: Data(bytes), completion: .contentProcessed { error in
                if let error { gate.fail(error) } else { gate.succeed(()) }
            })
        }
    }

    /// Waits for at least one byte. Returns `nil` on a clean close, throws
    /// `NetworkError.timedOut` if nothing arrives before the deadline.
    func receive(timeout: TimeInterval) async throws -> Data? {
        let gate = ContinuationGate<Data?>()
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data?, Error>) in
            gate.arm(cont)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { data, _, isComplete, error in
                if let error { gate.fail(error); return }
                if let data, !data.isEmpty { gate.succeed(data); return }
                if isComplete { gate.succeed(nil); return }
                gate.succeed(Data())
            }
            queue.asyncAfter(deadline: .now() + timeout) {
                _ = gate.failIfPending(NetworkError.timedOut)
            }
        }
    }

    func close() {
        connection.cancel()
    }
}

/// Guards a continuation so a timeout racing a callback can't resume it twice.
private final class ContinuationGate<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var cont: CheckedContinuation<T, Error>?

    func arm(_ c: CheckedContinuation<T, Error>) {
        lock.lock(); cont = c; lock.unlock()
    }

    func succeed(_ value: T) {
        lock.lock(); let c = cont; cont = nil; lock.unlock()
        c?.resume(returning: value)
    }

    func fail(_ error: Error) {
        lock.lock(); let c = cont; cont = nil; lock.unlock()
        c?.resume(throwing: error)
    }

    /// Returns true if this call is the one that resolved the continuation.
    @discardableResult
    func failIfPending(_ error: Error) -> Bool {
        lock.lock(); let c = cont; cont = nil; lock.unlock()
        guard let c else { return false }
        c.resume(throwing: error)
        return true
    }
}
