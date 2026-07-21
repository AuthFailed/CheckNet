import Foundation

/// What the path did with a hand-built ClientHello.
public struct JA3ProbeResult: Sendable, Hashable {
    public enum Reaction: String, Sendable, Codable {
        /// A ServerHello (or HelloRetryRequest) came back — the ClientHello was
        /// accepted by the far end. The handshake is intentionally abandoned.
        case serverHello
        /// The server replied with a TLS alert. The ClientHello still reached
        /// it, so this is not network interference.
        case tlsAlert
        /// `ECONNRESET` — something injected an RST after the ClientHello.
        case reset
        /// Silence past the deadline — the classic silent-drop signature.
        case timeout
        /// The peer closed cleanly with no reply.
        case closed
        /// Couldn't even establish TCP — not a fingerprint question.
        case tcpFailed

        public var label: String {
            switch self {
            case .serverHello: "рукопожатие принято"
            case .tlsAlert: "TLS-alert (ответ сервера)"
            case .reset: "сброс (RST)"
            case .timeout: "тишина после ClientHello"
            case .closed: "соединение закрыто"
            case .tcpFailed: "TCP не установлен"
            }
        }

        /// Whether this reaction looks like interference rather than a server or
        /// routing problem.
        public var suggestsInterference: Bool {
            switch self {
            case .reset, .timeout, .closed: true
            case .serverHello, .tlsAlert, .tcpFailed: false
            }
        }
    }

    public let profile: JA3Profile
    public let host: String
    public let serverName: String
    public let reaction: Reaction
    public let tcpConnected: Bool
    public let elapsedMillis: Double
    public let bytesReceived: Int
}

/// Sends a real browser-shaped ClientHello over a raw socket and reports how the
/// network reacted, without completing the handshake.
///
/// Detection only. We deliberately never finish the TLS handshake, negotiate
/// keys or transfer data — the ClientHello is a probe, not a connection.
public struct JA3Probe: Sendable {
    public init() {}

    /// - Parameters:
    ///   - host: address to connect to (IP or hostname; resolved if needed)
    ///   - serverName: SNI to place in the ClientHello — may differ from `host`,
    ///     which is what makes this usable for SNI-blocking tests
    public func run(
        host: String,
        serverName: String? = nil,
        profile: JA3Profile,
        port: UInt16 = 443,
        connectTimeout: TimeInterval = 6,
        replyTimeout: TimeInterval = 6
    ) async -> JA3ProbeResult {
        let sni = serverName ?? host
        let start = MonoClock.nanos()

        let endpoint: ResolvedEndpoint
        do {
            endpoint = try await HostResolver.resolveFirst(host: host, port: port)
        } catch {
            return result(profile, host, sni, .tcpFailed, tcp: false, start: start, bytes: 0)
        }

        // The socket work is blocking; keep it off the cooperative pool.
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let outcome = Self.probeBlocking(
                    endpoint: endpoint, sni: sni, profile: profile,
                    connectTimeout: connectTimeout, replyTimeout: replyTimeout
                )
                continuation.resume(returning: result(
                    profile, host, sni, outcome.reaction,
                    tcp: outcome.tcpConnected, start: start, bytes: outcome.bytes
                ))
            }
        }
    }

    private func result(
        _ profile: JA3Profile, _ host: String, _ sni: String, _ reaction: JA3ProbeResult.Reaction,
        tcp: Bool, start: UInt64, bytes: Int
    ) -> JA3ProbeResult {
        JA3ProbeResult(
            profile: profile, host: host, serverName: sni, reaction: reaction,
            tcpConnected: tcp, elapsedMillis: MonoClock.millisSince(start), bytesReceived: bytes
        )
    }

    // MARK: - Blocking socket work

    private static func probeBlocking(
        endpoint: ResolvedEndpoint, sni: String, profile: JA3Profile,
        connectTimeout: TimeInterval, replyTimeout: TimeInterval
    ) -> (reaction: JA3ProbeResult.Reaction, tcpConnected: Bool, bytes: Int) {
        let fd: Int32
        do {
            (fd, _) = try TCPTransport.connect(endpoint: endpoint, timeout: connectTimeout)
        } catch {
            return (.tcpFailed, false, 0)
        }
        defer { close(fd) }

        var rng = SystemRandomNumberGenerator()
        let hello = ClientHelloBuilder(profile: profile, serverName: sni).build(using: &rng)

        do {
            try TCPTransport.writeAll(fd: fd, bytes: hello)
        } catch {
            // Failing to even send after a successful connect is a reset in practice.
            return (classifyErrno(), true, 0)
        }

        // Read one TLS record header. Enough to tell handshake from alert.
        do {
            let header = try TCPTransport.readExactly(fd: fd, count: 5, timeout: replyTimeout)
            return (classifyRecord(header), true, header.count)
        } catch let error as NetworkError {
            switch error {
            case .timedOut:
                return (.timeout, true, 0)
            case .protocolError:
                // readExactly reports a clean close as a protocol error when it
                // gets fewer bytes than asked; distinguish by errno.
                return (errno == ECONNRESET ? .reset : .closed, true, 0)
            default:
                return (classifyErrno(), true, 0)
            }
        } catch {
            return (classifyErrno(), true, 0)
        }
    }

    /// First byte of a TLS record identifies its content type.
    private static func classifyRecord(_ header: [UInt8]) -> JA3ProbeResult.Reaction {
        guard let contentType = header.first else { return .closed }
        switch contentType {
        case 0x16: return .serverHello   // handshake — ServerHello / HelloRetryRequest
        case 0x15: return .tlsAlert      // alert
        default:   return .serverHello   // any well-formed record means it got through
        }
    }

    private static func classifyErrno() -> JA3ProbeResult.Reaction {
        switch errno {
        case ECONNRESET: return .reset
        case ETIMEDOUT: return .timeout
        default: return .closed
        }
    }
}
