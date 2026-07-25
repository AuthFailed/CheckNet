import Foundation
import Network
import Security

/// One TLS-1.3 endpoint found during a scan — a candidate Reality `dest`.
public struct RealityScanHit: Sendable, Hashable, Codable, Identifiable {
    public var id: String { ip }
    public let ip: String
    /// Domain taken from the leaf certificate (SAN or CN) — what you'd put in `serverNames`.
    public let domain: String
    public let issuer: String
    public let tlsVersion: String
    public let alpn: String?
    /// Whether the server negotiated HTTP/2 — a Reality `dest` needs it.
    public let supportsH2: Bool
    public let handshakeMillis: Double

    public init(ip: String, domain: String, issuer: String, tlsVersion: String,
                alpn: String?, supportsH2: Bool, handshakeMillis: Double) {
        self.ip = ip
        self.domain = domain
        self.issuer = issuer
        self.tlsVersion = tlsVersion
        self.alpn = alpn
        self.supportsH2 = supportsH2
        self.handshakeMillis = handshakeMillis
    }
}

public enum RealityScanEvent: Sendable {
    case progress(scanned: Int, total: Int)
    case hit(RealityScanHit)
    case finished(hitCount: Int)
    case failed(String)
}

/// Sweeps an IPv4 range looking for endpoints usable as a Reality `dest` — the
/// job `XTLS/RealiTLScanner` does. For each address it opens a TLS 1.3 handshake
/// **without SNI** and keeps the ones that answer with TLS 1.3 and a real leaf
/// certificate, reading the certificate's domain (SAN/CN) and issuer. Built on
/// Network.framework (raw sockets are unavailable on iOS and in the sandbox),
/// reusing the range parser and streaming shape of `IPRangeScanner`.
///
/// Diagnostics only: it helps an operator find a plausible camouflage domain
/// hosted near their own server. It performs no DPI bypass.
public final class RealityScanner: Sendable {
    public init() {}

    /// - Parameters:
    ///   - target: CIDR, `a.b.c.d-e`, `a.b.c`, a single IP, or a domain (resolved to its IP).
    ///   - requireH2: keep only endpoints that also negotiate HTTP/2 (RealiTLScanner's rule).
    public func scan(
        target: String,
        port: Int = 443,
        requireH2: Bool = false,
        timeout: TimeInterval = 5,
        concurrency: Int = 32
    ) -> AsyncStream<RealityScanEvent> {
        AsyncStream(bufferingPolicy: .unbounded) { continuation in
            let task = Task {
                guard let hosts = await Self.resolveTargets(target, port: port), !hosts.isEmpty else {
                    continuation.yield(.failed("Не удалось разобрать цель: \(target)"))
                    continuation.finish()
                    return
                }

                let total = hosts.count
                var scanned = 0
                var hitCount = 0

                await withTaskGroup(of: RealityScanHit?.self) { group in
                    var iterator = hosts.makeIterator()
                    var active = 0
                    func addNext() {
                        guard let ip = iterator.next() else { return }
                        active += 1
                        group.addTask {
                            await Self.probe(ip: ip, port: port, requireH2: requireH2, timeout: timeout)
                        }
                    }
                    for _ in 0..<max(1, concurrency) { addNext() }
                    while active > 0 {
                        guard let result = await group.next() else { break }
                        active -= 1
                        scanned += 1
                        continuation.yield(.progress(scanned: scanned, total: total))
                        if let hit = result {
                            hitCount += 1
                            continuation.yield(.hit(hit))
                        }
                        if Task.isCancelled { break }
                        addNext()
                    }
                    group.cancelAll()
                }
                continuation.yield(.finished(hitCount: hitCount))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Expands `target` into IPv4 literals. A range/CIDR uses `IPv4Range`; anything
    /// else is treated as a hostname and resolved to its first address.
    static func resolveTargets(_ target: String, port: Int) async -> [String]? {
        if let hosts = IPv4Range.hosts(from: target) { return hosts }
        // Not a range → maybe a domain. Resolve it to one IP and scan that.
        if let endpoint = try? await HostResolver.resolveFirst(host: target, port: UInt16(port), family: .ipv4) {
            return [endpoint.ipString]
        }
        return nil
    }

    /// Opens a no-SNI TLS handshake to `ip:port`, returning a hit when the server
    /// answers with TLS 1.3 and a readable leaf certificate.
    static func probe(ip: String, port: Int, requireH2: Bool, timeout: TimeInterval) async -> RealityScanHit? {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else { return nil }

        let box = ScanTrustBox()
        let tlsOptions = NWProtocolTLS.Options()
        let sec = tlsOptions.securityProtocolOptions
        // Deliberately no server_name: like RealiTLScanner's IP scan, we want the
        // server's default certificate, which is where the camouflage domain lives.
        for proto in ["h2", "http/1.1"] {
            sec_protocol_options_add_tls_application_protocol(sec, proto)
        }
        let verifyQueue = DispatchQueue(label: "networkkit.reality.scan.verify")
        sec_protocol_options_set_verify_block(sec, { _, trust, complete in
            box.store(sec_trust_copy_ref(trust).takeRetainedValue())
            complete(true)
        }, verifyQueue)

        let params = NWParameters(tls: tlsOptions)
        let connection = NWConnection(host: NWEndpoint.Host(ip), port: nwPort, using: params)
        let start = MonoClock.nanos()
        let gate = HitGate()

        return await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<RealityScanHit?, Never>) in
                gate.arm(cont)
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        let ms = MonoClock.millisSince(start)
                        let meta = connection.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata
                        let hit = Self.buildHit(ip: ip, handshake: ms, metadata: meta,
                                                trust: box.trust(), requireH2: requireH2)
                        connection.cancel()
                        gate.finish(hit)
                    case .failed, .cancelled:
                        gate.finish(nil)
                    default:
                        break
                    }
                }
                connection.start(queue: verifyQueue)
                verifyQueue.asyncAfter(deadline: .now() + timeout) {
                    if gate.finish(nil) { connection.cancel() }
                }
            }
        } onCancel: {
            connection.cancel()
        }
    }

    static func buildHit(
        ip: String, handshake: Double, metadata: NWProtocolTLS.Metadata?,
        trust: SecTrust?, requireH2: Bool
    ) -> RealityScanHit? {
        guard let metadata else { return nil }
        let secMeta = metadata.securityProtocolMetadata
        let version = sec_protocol_metadata_get_negotiated_tls_protocol_version(secMeta)
        guard version == .TLSv13 else { return nil }   // Reality requires TLS 1.3.

        var alpn: String? = nil
        if let neg = sec_protocol_metadata_get_negotiated_protocol(secMeta) {
            alpn = String(cString: neg)
        }
        let h2 = alpn == "h2"
        if requireH2 && !h2 { return nil }

        guard let trust,
              let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = chain.first else { return nil }
        let der = [UInt8](SecCertificateCopyData(leaf) as Data)
        let fields = X509.parse(der: der)
        let cn = commonName(from: fields?.subject) ?? (SecCertificateCopySubjectSummary(leaf) as String?)
        let domain = fields?.subjectAltNames.first(where: { !$0.contains(":") }) ?? cn
        guard let domain, !domain.isEmpty else { return nil }
        let issuer = commonName(from: fields?.issuer) ?? fields?.issuer ?? "—"

        return RealityScanHit(
            ip: ip, domain: domain, issuer: issuer,
            tlsVersion: "TLS 1.3", alpn: alpn, supportsH2: h2, handshakeMillis: handshake
        )
    }

    /// Pulls the CN out of an RFC 4514 name string like "CN=example.com, O=…".
    static func commonName(from name: String?) -> String? {
        guard let name else { return nil }
        for part in name.split(separator: ",") {
            let p = part.trimmingCharacters(in: .whitespaces)
            if p.lowercased().hasPrefix("cn=") { return String(p.dropFirst(3)) }
        }
        return nil
    }
}

/// Thread-safe holder for the SecTrust captured in the verify block.
private final class ScanTrustBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: SecTrust?
    func store(_ t: SecTrust) { lock.lock(); value = t; lock.unlock() }
    func trust() -> SecTrust? { lock.lock(); defer { lock.unlock() }; return value }
}

/// Resolves a hit continuation exactly once across ready/failed/timeout.
private final class HitGate: @unchecked Sendable {
    private let lock = NSLock()
    private var cont: CheckedContinuation<RealityScanHit?, Never>?
    func arm(_ c: CheckedContinuation<RealityScanHit?, Never>) { lock.lock(); cont = c; lock.unlock() }
    @discardableResult
    func finish(_ value: RealityScanHit?) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let c = cont else { return false }
        cont = nil
        c.resume(returning: value)
        return true
    }
}
