import Foundation
import Network
import Security
import CryptoKit

public struct TLSCertificate: Sendable, Hashable, Codable, Identifiable {
    public var id: String { serialNumber + subject }
    public let subject: String
    public let issuer: String
    public let notBefore: Date?
    public let notAfter: Date?
    public let serialNumber: String
    public let sha256Fingerprint: String
    public let isCA: Bool
    public let subjectAltNames: [String]

    public var isExpired: Bool {
        guard let notAfter else { return false }
        return Date() > notAfter
    }
    public var isNotYetValid: Bool {
        guard let notBefore else { return false }
        return Date() < notBefore
    }
    public var daysUntilExpiry: Int? {
        guard let notAfter else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: notAfter).day
    }
}

public struct TLSInfo: Sendable, Hashable, Codable {
    public let host: String
    public let port: Int
    public let resolvedIP: String
    public let negotiatedProtocol: String     // e.g. "TLS 1.3"
    public let cipherSuite: String
    public let alpn: String?
    public let handshakeMillis: Double
    public let trustEvaluationPassed: Bool
    public let certificates: [TLSCertificate]

    public var leaf: TLSCertificate? { certificates.first }
}

/// Inspects a TLS endpoint: negotiated version, cipher, ALPN, and the full
/// certificate chain with validity dates. Built on Network.framework, so it
/// works identically on iOS and macOS.
public final class TLSInspector: Sendable {
    public init() {}

    public func inspect(
        host: String,
        port: Int = 443,
        serverName: String? = nil,
        alpnProtocols: [String] = ["h2", "http/1.1"],
        timeout: TimeInterval = 8.0
    ) async throws -> TLSInfo {
        let endpoint = try await HostResolver.resolveFirst(host: host, port: UInt16(port))
        let sni = serverName ?? host

        let box = TrustBox()
        let tlsOptions = NWProtocolTLS.Options()
        let sec = tlsOptions.securityProtocolOptions
        sec_protocol_options_set_tls_server_name(sec, sni)
        for proto in alpnProtocols {
            sec_protocol_options_add_tls_application_protocol(sec, proto)
        }
        // Capture the trust object; accept the handshake regardless of validity so
        // we can still report on expired/invalid certificates.
        let verifyQueue = DispatchQueue(label: "networkkit.tls.verify")
        sec_protocol_options_set_verify_block(sec, { _, trust, complete in
            let secTrust = sec_trust_copy_ref(trust).takeRetainedValue()
            box.store(secTrust)
            complete(true)
        }, verifyQueue)

        let params = NWParameters(tls: tlsOptions)
        let nwHost = NWEndpoint.Host(endpoint.ipString)
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            throw NetworkError.protocolError("некорректный порт")
        }
        let connection = NWConnection(host: nwHost, port: nwPort, using: params)

        let start = MonoClock.nanos()
        let state = ConnectionWaiter()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<TLSInfo, Error>) in
                state.setContinuation(cont)
                connection.stateUpdateHandler = { newState in
                    switch newState {
                    case .ready:
                        let handshake = MonoClock.millisSince(start)
                        let metadata = connection.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata
                        let info = Self.buildInfo(
                            host: host, port: port, ip: endpoint.ipString,
                            handshake: handshake, metadata: metadata, trust: box.trust()
                        )
                        connection.cancel()
                        state.resume(returning: info)
                    case .failed(let error):
                        connection.cancel()
                        state.resume(throwing: NetworkError.tls(error.localizedDescription))
                    case .cancelled:
                        state.resume(throwing: NetworkError.cancelled)
                    default:
                        break
                    }
                }
                connection.start(queue: DispatchQueue.global(qos: .userInitiated))
                verifyQueue.asyncAfter(deadline: .now() + timeout) {
                    if state.resumeIfPending(throwing: NetworkError.timedOut) {
                        connection.cancel()
                    }
                }
            }
        } onCancel: {
            connection.cancel()
        }
    }

    private static func buildInfo(
        host: String, port: Int, ip: String, handshake: Double,
        metadata: NWProtocolTLS.Metadata?, trust: SecTrust?
    ) -> TLSInfo {
        var proto = "—"
        var cipher = "—"
        var alpn: String? = nil
        if let metadata {
            let secMeta = metadata.securityProtocolMetadata
            proto = tlsVersionString(sec_protocol_metadata_get_negotiated_tls_protocol_version(secMeta))
            cipher = cipherString(sec_protocol_metadata_get_negotiated_tls_ciphersuite(secMeta))
            if let neg = sec_protocol_metadata_get_negotiated_protocol(secMeta) {
                alpn = String(cString: neg)
            }
        }

        var certs: [TLSCertificate] = []
        var trustPassed = false
        if let trust {
            var err: CFError?
            trustPassed = SecTrustEvaluateWithError(trust, &err)
            certs = extractCertificates(trust)
        }

        return TLSInfo(
            host: host, port: port, resolvedIP: ip,
            negotiatedProtocol: proto, cipherSuite: cipher, alpn: alpn,
            handshakeMillis: handshake, trustEvaluationPassed: trustPassed,
            certificates: certs
        )
    }

    private static func extractCertificates(_ trust: SecTrust) -> [TLSCertificate] {
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate] else { return [] }
        return chain.map { cert in
            let der = [UInt8](SecCertificateCopyData(cert) as Data)
            let fields = X509.parse(der: der)
            // SecCertificateCopySubjectSummary gives a friendly leaf name on all platforms.
            let summary = SecCertificateCopySubjectSummary(cert) as String?
            let subject = fields?.subject.isEmpty == false ? fields!.subject : (summary ?? "—")
            let issuer = fields?.issuer.isEmpty == false ? fields!.issuer : "—"
            let serial = certSerial(cert)
            let fingerprint = sha256Hex(SecCertificateCopyData(cert) as Data)
            return TLSCertificate(
                subject: subject,
                issuer: issuer,
                notBefore: fields?.notBefore,
                notAfter: fields?.notAfter,
                serialNumber: serial,
                sha256Fingerprint: fingerprint,
                isCA: fields?.isCA ?? false,
                subjectAltNames: fields?.subjectAltNames ?? []
            )
        }
    }

    private static func certSerial(_ cert: SecCertificate) -> String {
        guard let data = SecCertificateCopySerialNumberData(cert, nil) as Data? else { return "—" }
        return data.map { String(format: "%02X", $0) }.joined(separator: ":")
    }

    private static func tlsVersionString(_ v: tls_protocol_version_t) -> String {
        switch v {
        case .TLSv10: return "TLS 1.0"
        case .TLSv11: return "TLS 1.1"
        case .TLSv12: return "TLS 1.2"
        case .TLSv13: return "TLS 1.3"
        case .DTLSv10: return "DTLS 1.0"
        case .DTLSv12: return "DTLS 1.2"
        @unknown default: return "—"
        }
    }

    private static func cipherString(_ suite: tls_ciphersuite_t) -> String {
        switch suite {
        case .AES_128_GCM_SHA256: return "TLS_AES_128_GCM_SHA256"
        case .AES_256_GCM_SHA384: return "TLS_AES_256_GCM_SHA384"
        case .CHACHA20_POLY1305_SHA256: return "TLS_CHACHA20_POLY1305_SHA256"
        case .ECDHE_ECDSA_WITH_AES_128_GCM_SHA256: return "ECDHE_ECDSA_AES128_GCM_SHA256"
        case .ECDHE_RSA_WITH_AES_128_GCM_SHA256: return "ECDHE_RSA_AES128_GCM_SHA256"
        case .ECDHE_ECDSA_WITH_AES_256_GCM_SHA384: return "ECDHE_ECDSA_AES256_GCM_SHA384"
        case .ECDHE_RSA_WITH_AES_256_GCM_SHA384: return "ECDHE_RSA_AES256_GCM_SHA384"
        case .ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256: return "ECDHE_RSA_CHACHA20_POLY1305"
        case .ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256: return "ECDHE_ECDSA_CHACHA20_POLY1305"
        default: return String(format: "0x%04X", suite.rawValue)
        }
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02X", $0) }.joined(separator: ":")
    }
}

/// Thread-safe holder for the SecTrust captured in the verify block.
private final class TrustBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: SecTrust?
    func store(_ t: SecTrust) { lock.lock(); value = t; lock.unlock() }
    func trust() -> SecTrust? { lock.lock(); defer { lock.unlock() }; return value }
}

/// Ensures the continuation resumes exactly once across handshake/timeout/cancel.
private final class ConnectionWaiter: @unchecked Sendable {
    private let lock = NSLock()
    private var cont: CheckedContinuation<TLSInfo, Error>?
    private var done = false

    func setContinuation(_ c: CheckedContinuation<TLSInfo, Error>) {
        lock.lock(); cont = c; lock.unlock()
    }
    func resume(returning value: TLSInfo) {
        lock.lock(); defer { lock.unlock() }
        guard !done, let c = cont else { return }
        done = true; cont = nil
        c.resume(returning: value)
    }
    func resume(throwing error: Error) {
        lock.lock(); defer { lock.unlock() }
        guard !done, let c = cont else { return }
        done = true; cont = nil
        c.resume(throwing: error)
    }
    /// Returns true if it actually resumed (was still pending).
    func resumeIfPending(throwing error: Error) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !done, let c = cont else { return false }
        done = true; cont = nil
        c.resume(throwing: error)
        return true
    }
}
