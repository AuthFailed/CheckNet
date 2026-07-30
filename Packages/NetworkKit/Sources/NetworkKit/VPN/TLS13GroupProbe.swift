import Foundation
import Network
import CryptoKit

/// Detects whether a TLS 1.3 server supports the **X25519** key-exchange group.
///
/// Network.framework offers no way to restrict the offered curves, so — like
/// `XTLS/RealiTLScanner`, which pins `CurvePreferences` to X25519 — we send a
/// minimal TLS 1.3 ClientHello that advertises X25519 as the *only* supported
/// group and key share. If the server answers with a ServerHello it accepted
/// X25519; a `handshake_failure` alert (or anything that isn't a ServerHello)
/// means it couldn't. We never finish the handshake or send application data.
enum TLS13GroupProbe {

    /// The 32-byte "HelloRetryRequest" sentinel that occupies ServerHello.random
    /// (RFC 8446 §4.1.3). We only offer one group, so a real HRR can't ask for a
    /// different one — but we still guard against it.
    private static let helloRetryRandom: [UInt8] = [
        0xCF, 0x21, 0xAD, 0x74, 0xE5, 0x9A, 0x61, 0x11, 0xBE, 0x1D, 0x8C, 0x02, 0x1E, 0x65, 0xB8, 0x91,
        0xC2, 0xA2, 0x11, 0x16, 0x7A, 0xBB, 0x8C, 0x5E, 0x07, 0x9E, 0x09, 0xE2, 0xC8, 0xA8, 0x33, 0x9C,
    ]

    private static let x25519Group: UInt16 = 0x001d

    /// Connects to `ip:port` over plain TCP (via Network.framework, so it works
    /// on iOS/macOS alike), sends the X25519-only ClientHello with `serverName`
    /// as SNI, and reports whether the server produced a ServerHello.
    static func supportsX25519(ip: String, port: Int, serverName: String, timeout: TimeInterval) async -> Bool {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else { return false }
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        let params = NWParameters(tls: nil, tcp: tcp)
        let connection = NWConnection(host: NWEndpoint.Host(ip), port: nwPort, using: params)
        let queue = DispatchQueue(label: "networkkit.reality.x25519")

        return await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                let gate = ResultGate(cont)
                let hello = clientHello(serverName: serverName)

                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        connection.send(content: Data(hello), completion: .contentProcessed { error in
                            if error != nil { gate.finish(false); connection.cancel(); return }
                            readServerHello(connection, timeout: timeout, queue: queue) { ok in
                                gate.finish(ok); connection.cancel()
                            }
                        })
                    case .failed, .cancelled:
                        gate.finish(false)
                    default:
                        break
                    }
                }
                connection.start(queue: queue)
                queue.asyncAfter(deadline: .now() + timeout) {
                    if gate.finish(false) { connection.cancel() }
                }
            }
        } onCancel: {
            connection.cancel()
        }
    }

    /// Reads the first TLS record (5-byte header + body) and reports whether it
    /// is a ServerHello.
    private static func readServerHello(
        _ connection: NWConnection, timeout: TimeInterval, queue: DispatchQueue,
        completion: @escaping @Sendable (Bool) -> Void
    ) {
        receiveExactly(connection, count: 5) { header in
            guard let header, header.count == 5, header[0] == 0x16 else { completion(false); return }
            let length = Int(header[3]) << 8 | Int(header[4])
            guard length > 0, length < 1 << 14 else { completion(false); return }
            receiveExactly(connection, count: length) { body in
                guard let body else { completion(false); return }
                completion(isServerHello([UInt8](body)))
            }
        }
    }

    /// Accumulates exactly `count` bytes from the connection, or `nil` on close/error.
    private static func receiveExactly(
        _ connection: NWConnection, count: Int, into acc: Data = Data(),
        completion: @escaping @Sendable (Data?) -> Void
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: count - acc.count) { data, _, isComplete, error in
            if error != nil { completion(nil); return }
            var next = acc
            if let data { next.append(data) }
            if next.count >= count { completion(next.prefix(count)); return }
            if isComplete { completion(nil); return }
            receiveExactly(connection, count: count, into: next, completion: completion)
        }
    }

    /// A handshake record body starts with [type, len(3), ...]. Type 0x02 is
    /// ServerHello; we reject the HelloRetryRequest disguise.
    static func isServerHello(_ handshake: [UInt8]) -> Bool {
        guard handshake.count >= 38, handshake[0] == 0x02 else { return false }
        // handshake[1...3] = length; handshake[4..5] = legacy_version; [6..37] = random.
        let random = Array(handshake[6..<38])
        return random != helloRetryRandom
    }

    // MARK: - ClientHello construction

    static func clientHello(serverName: String) -> [UInt8] {
        var body: [UInt8] = []
        body += [0x03, 0x03]                                   // legacy_version = TLS 1.2
        body += (0..<32).map { _ in UInt8.random(in: 0...255) } // random

        let sessionID = (0..<32).map { _ in UInt8.random(in: 0...255) }
        body += [UInt8(sessionID.count)] + sessionID           // legacy_session_id (middlebox compat)

        // cipher_suites: the three TLS 1.3 suites.
        let ciphers: [UInt8] = [0x13, 0x01, 0x13, 0x02, 0x13, 0x03]
        body += u16(ciphers.count) + ciphers

        body += [0x01, 0x00]                                    // compression: [null]

        body += lengthPrefixed16(extensions(serverName: serverName))

        // Wrap in a handshake header (type 0x01 = ClientHello) then a TLS record.
        let handshake = [0x01] + u24(body.count) + body
        let record: [UInt8] = [0x16, 0x03, 0x01] + u16(handshake.count) + handshake
        return record
    }

    private static func extensions(serverName: String) -> [UInt8] {
        var ext: [UInt8] = []

        // server_name (0x0000)
        let hostBytes = Array(serverName.utf8)
        let sniEntry = [0x00] + u16(hostBytes.count) + hostBytes         // host_name type + name
        let sniList = u16(sniEntry.count) + sniEntry
        ext += extension_(0x0000, sniList)

        // supported_groups (0x000a): X25519 only — the whole point of the probe.
        let groups = u16(2) + u16(Int(x25519Group))
        ext += extension_(0x000a, groups)

        // signature_algorithms (0x000d): a common set so TLS 1.3 servers are happy.
        let sigAlgs: [UInt16] = [0x0403, 0x0804, 0x0401, 0x0503, 0x0805, 0x0501, 0x0806, 0x0601, 0x0203]
        var sigBytes: [UInt8] = []
        for s in sigAlgs { sigBytes += u16(Int(s)) }
        ext += extension_(0x000d, u16(sigBytes.count) + sigBytes)

        // supported_versions (0x002b): TLS 1.3 only.
        ext += extension_(0x002b, [0x02, 0x03, 0x04])

        // key_share (0x0033): one X25519 share with a real public key.
        let pub = Array(Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation)
        let entry = u16(Int(x25519Group)) + u16(pub.count) + pub
        ext += extension_(0x0033, u16(entry.count) + entry)

        return ext
    }

    // MARK: - Encoding helpers

    private static func extension_(_ type: UInt16, _ data: [UInt8]) -> [UInt8] {
        u16(Int(type)) + u16(data.count) + data
    }
    private static func lengthPrefixed16(_ data: [UInt8]) -> [UInt8] { u16(data.count) + data }
    private static func u16(_ v: Int) -> [UInt8] { [UInt8((v >> 8) & 0xff), UInt8(v & 0xff)] }
    private static func u24(_ v: Int) -> [UInt8] { [UInt8((v >> 16) & 0xff), UInt8((v >> 8) & 0xff), UInt8(v & 0xff)] }
}

/// Resolves a `Bool` continuation exactly once across ready/send/read/timeout.
private final class ResultGate: @unchecked Sendable {
    private let lock = NSLock()
    private var cont: CheckedContinuation<Bool, Never>?
    init(_ c: CheckedContinuation<Bool, Never>) { cont = c }
    /// Returns true if this call is the one that resolved the continuation.
    @discardableResult
    func finish(_ value: Bool) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let c = cont else { return false }
        cont = nil
        c.resume(returning: value)
        return true
    }
}
