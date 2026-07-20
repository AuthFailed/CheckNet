import Foundation
import Network

/// How our ClientHello should look.
///
/// This matters because some filtering is fingerprint-conditional: the
/// `dpi-checkers` project observes the "Siberian" connection-rate restriction
/// firing on a Chrome-like handshake and *not* on an Edge-like one. A checker
/// that only ever sends one handshake shape can report "clean" on a network
/// where the user's browser is being cut off.
///
/// **Honest limitation.** Network.framework owns the ClientHello: extension
/// order, GREASE values and the exact cipher list come from Apple's TLS stack.
/// So these profiles are *not* faithful JA3 impersonations of Chrome or
/// Firefox, and nothing here should be presented as such. What they do change
/// is real and observable — protocol version bounds, the offered cipher suites,
/// and ALPN — which is enough to answer "does the outcome depend on how the
/// handshake looks?" A negative result narrows nothing; a *divergent* result is
/// meaningful evidence.
public enum TLSFingerprint: String, Sendable, Codable, CaseIterable, Identifiable {
    /// Whatever Apple's stack negotiates by default.
    case system
    /// Cap at TLS 1.2 — the shape older middleboxes parse most reliably.
    case tls12
    /// Require TLS 1.3.
    case tls13
    /// TLS 1.3 with no ALPN offered at all.
    case noALPN
    /// A deliberately narrow cipher list, so the ClientHello is small.
    case minimalCiphers

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .system: "Системный (Apple)"
        case .tls12: "TLS 1.2"
        case .tls13: "TLS 1.3"
        case .noALPN: "TLS 1.3 без ALPN"
        case .minimalCiphers: "Узкий набор шифров"
        }
    }

    public var detail: String {
        switch self {
        case .system: "Стандартное рукопожатие iOS с ALPN h2/http1.1."
        case .tls12: "Ограничение до TLS 1.2 — так выглядят соединения старых клиентов."
        case .tls13: "Только TLS 1.3."
        case .noALPN: "TLS 1.3 без списка протоколов приложения."
        case .minimalCiphers: "Минимальный список шифров — самое короткое рукопожатие."
        }
    }

    var alpnProtocols: [String] {
        switch self {
        case .noALPN: []
        default: ["h2", "http/1.1"]
        }
    }

    /// Applies the profile to a TLS options block.
    func apply(to options: NWProtocolTLS.Options) {
        let sec = options.securityProtocolOptions
        switch self {
        case .system:
            break
        case .tls12:
            sec_protocol_options_set_min_tls_protocol_version(sec, .TLSv12)
            sec_protocol_options_set_max_tls_protocol_version(sec, .TLSv12)
        case .tls13, .noALPN:
            sec_protocol_options_set_min_tls_protocol_version(sec, .TLSv13)
            sec_protocol_options_set_max_tls_protocol_version(sec, .TLSv13)
        case .minimalCiphers:
            sec_protocol_options_set_min_tls_protocol_version(sec, .TLSv12)
            sec_protocol_options_set_max_tls_protocol_version(sec, .TLSv12)
            sec_protocol_options_append_tls_ciphersuite(sec, .ECDHE_RSA_WITH_AES_128_GCM_SHA256)
            sec_protocol_options_append_tls_ciphersuite(sec, .ECDHE_RSA_WITH_AES_256_GCM_SHA384)
        }
        for proto in alpnProtocols {
            sec_protocol_options_add_tls_application_protocol(sec, proto)
        }
    }
}
