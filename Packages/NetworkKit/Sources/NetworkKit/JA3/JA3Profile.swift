import Foundation

/// A browser TLS fingerprint: the cipher list, groups, signature algorithms,
/// extension order and GREASE behaviour that together make a ClientHello look
/// like a specific browser.
///
/// Filtering can be fingerprint-conditional. The dpi-checkers project and the
/// habr write-up both note that Chrome- and Safari-shaped handshakes draw more
/// scrutiny in "suspicious" subnets, while Firefox, Edge and the Android stack
/// are treated as loyal. Offering the real profiles lets a user find out which
/// case their network is in.
public enum JA3Profile: String, Sendable, CaseIterable, Identifiable, Codable {
    case chrome
    case firefox
    case safari

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .chrome: "Chrome"
        case .firefox: "Firefox"
        case .safari: "Safari"
        }
    }

    public var detail: String {
        switch self {
        case .chrome: "Реальное рукопожатие Chrome: GREASE, ALPS, порядок расширений Chromium."
        case .firefox: "Реальное рукопожатие Firefox: без GREASE-cipher, свой набор групп и расширений."
        case .safari: "Реальное рукопожатие Safari/WebKit."
        }
    }

    var usesGREASE: Bool {
        switch self {
        case .chrome, .safari: true
        case .firefox: false
        }
    }

    /// Cipher suites, in the browser's real order (GREASE, when used, is
    /// prepended by the builder).
    var cipherSuites: [UInt16] {
        switch self {
        case .chrome:
            [0x1301, 0x1302, 0x1303, 0xc02b, 0xc02f, 0xc02c, 0xc030,
             0xcca9, 0xcca8, 0xc013, 0xc014, 0x009c, 0x009d, 0x002f, 0x0035]
        case .firefox:
            [0x1301, 0x1303, 0x1302, 0xc02b, 0xc02f, 0xcca9, 0xcca8, 0xc02c,
             0xc030, 0xc00a, 0xc009, 0xc013, 0xc014, 0x009c, 0x009d, 0x002f, 0x0035, 0x000a]
        case .safari:
            [0x1301, 0x1302, 0x1303, 0xc02c, 0xc02b, 0xc030, 0xc02f, 0xcca9, 0xcca8,
             0xc00a, 0xc009, 0xc014, 0xc013, 0x009d, 0x009c, 0x0035, 0x002f, 0x000a]
        }
    }

    var supportedGroups: [UInt16] {
        switch self {
        case .chrome:  [0x001d, 0x0017, 0x0018]                 // x25519, secp256r1, secp384r1
        case .firefox: [0x001d, 0x0017, 0x0018, 0x0019, 0x0100, 0x0101] // + secp521r1, ffdhe2048/3072
        case .safari:  [0x001d, 0x0017, 0x0018, 0x0019]
        }
    }

    var signatureAlgorithms: [UInt16] {
        switch self {
        case .chrome:
            [0x0403, 0x0804, 0x0401, 0x0503, 0x0805, 0x0501, 0x0806, 0x0601]
        case .firefox:
            [0x0403, 0x0503, 0x0603, 0x0804, 0x0805, 0x0806, 0x0401, 0x0501, 0x0601, 0x0203, 0x0201]
        case .safari:
            [0x0403, 0x0804, 0x0401, 0x0503, 0x0203, 0x0805, 0x0501, 0x0806, 0x0601, 0x0201]
        }
    }

    var alpn: [String] { ["h2", "http/1.1"] }

    /// Which extensions to emit, in order. Chrome shuffles most of these at
    /// runtime, but a fixed realistic order is enough to answer "does the
    /// outcome depend on the fingerprint".
    var extensionOrder: [ExtensionKind] {
        switch self {
        case .chrome:
            [.grease, .serverName, .extendedMasterSecret, .renegotiationInfo,
             .supportedGroups, .ecPointFormats, .sessionTicket, .alpn, .statusRequest,
             .signatureAlgorithms, .signedCertTimestamp, .keyShare, .pskKeyExchangeModes,
             .supportedVersions, .compressCertificate, .applicationSettings, .grease, .padding]
        case .firefox:
            [.serverName, .extendedMasterSecret, .renegotiationInfo, .supportedGroups,
             .ecPointFormats, .sessionTicket, .alpn, .statusRequest, .delegatedCredentials,
             .keyShare, .supportedVersions, .signatureAlgorithms, .pskKeyExchangeModes,
             .recordSizeLimit]
        case .safari:
            [.grease, .serverName, .extendedMasterSecret, .renegotiationInfo,
             .supportedGroups, .ecPointFormats, .alpn, .statusRequest, .signatureAlgorithms,
             .signedCertTimestamp, .keyShare, .pskKeyExchangeModes, .supportedVersions,
             .compressCertificate, .grease, .padding]
        }
    }

    enum ExtensionKind {
        case grease, serverName, extendedMasterSecret, renegotiationInfo, supportedGroups
        case ecPointFormats, sessionTicket, alpn, statusRequest, signatureAlgorithms
        case signedCertTimestamp, keyShare, pskKeyExchangeModes, supportedVersions
        case compressCertificate, applicationSettings, delegatedCredentials, recordSizeLimit, padding
    }
}
