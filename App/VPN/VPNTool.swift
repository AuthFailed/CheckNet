import SwiftUI

/// Tools in the **VPN** tab — utilities for people who *run* a VPN
/// (Xray / Reality / mihomo / Happ ecosystem), as opposed to the end-user
/// diagnostics in the Tests tab. Kept as its own type, like `BlockingCheck`,
/// so the main catalog stays about network diagnostics.
///
/// Scope is diagnostics and config management — inspect, parse, build, check.
/// The app performs no DPI-bypass; it helps an operator set up and verify their
/// own server.
enum VPNTool: String, CaseIterable, Identifiable {
    // Links & subscriptions
    case happRouting
    case subscription
    case happDecrypt
    case incyLink
    // Server checks
    case sniCheck
    case realityScanner
    case xrayCheck
    // Lists & data
    case geoData
    case mrsViewer
    case clientHeaders

    var id: String { rawValue }

    var title: String {
        switch self {
        case .happRouting: "Happ routing"
        case .subscription: "Subscription parsing"
        case .happDecrypt: "Happ Decrypt"
        case .incyLink: "Incy link"
        case .sniCheck: "SNI check for Reality"
        case .realityScanner: "Scanner for Reality"
        case .xrayCheck: "Xray availability"
        case .geoData: "geosite / geoip"
        case .mrsViewer: "mihomo rules (.mrs)"
        case .clientHeaders: "Client headers"
        }
    }

    var subtitle: String {
        switch self {
        case .happRouting: "Parse and build routing rules"
        case .subscription: "Hosts and routing from a subscription"
        case .happDecrypt: "Decrypt happ://crypt links"
        case .incyLink: "Parse and generate incy://crypt1"
        case .sniCheck: "Whether the domain works as dest"
        case .realityScanner: "Find TLS 1.3 domains in a subnet"
        case .xrayCheck: "Whether the VLESS/Trojan inbound is alive"
        case .geoData: "View .dat: categories, search"
        case .mrsViewer: "Unpack rule-set into rules"
        case .clientHeaders: "What the server returns to different clients"
        }
    }

    var systemImage: String {
        switch self {
        case .happRouting: "arrow.triangle.branch"
        case .subscription: "list.bullet.rectangle"
        case .happDecrypt: "lock.open"
        case .incyLink: "link.badge.plus"
        case .sniCheck: "checkmark.shield"
        case .realityScanner: "dot.radiowaves.left.and.right"
        case .xrayCheck: "bolt.horizontal.circle"
        case .geoData: "globe.badge.chevron.backward"
        case .mrsViewer: "doc.plaintext"
        case .clientHeaders: "person.2.badge.gearshape"
        }
    }

    /// The "what & why" shown behind the ⓘ button and, for unbuilt tools, on the
    /// placeholder screen.
    var info: String {
        switch self {
        case .happRouting:
            "Parses a `happ://routing/add/…` link into a readable profile (DNS, strategy, Direct/Proxy/Block lists) and builds the link back. Import existing rules and generate new ones for the Happ client."
        case .subscription:
            "Parses a subscription (base64 links, Clash YAML, sing-box JSON, Happ/Incy) and shows the node list, parameters, and built-in routing with quick jumps to checks."
        case .happDecrypt:
            "Decrypts `happ://crypt…` links (usually a subscription or config) into readable form. Everything is computed on the device."
        case .incyLink:
            "Parses `incy://crypt1/…` into a subscription URL and generates such a link from your own URL — so you can hand users a link and QR instead of a bare address."
        case .sniCheck:
            "Checks whether a domain works as an SNI/dest for Reality: TLS 1.3, HTTP/2, no redirect, certificate, geo, and reachability — with a final verdict."
        case .realityScanner:
            "Walks an IP address, subnet (CIDR), or domain and finds hosts with TLS 1.3, showing the domain from their certificate — dest candidates near your server. The handshake runs without SNI, as in RealiTLScanner. Discovery only, no censorship circumvention."
        case .xrayCheck:
            "Performs a real handshake to your inbound (VLESS/Trojan) and a test request through the server to confirm it works, and names the cause on failure."
        case .geoData:
            "Opens your `geosite.dat` / `geoip.dat` files: categories and tags, domain/IP lookup by category, filters and sorting, export."
        case .mrsViewer:
            "Unpacks a compiled mihomo rule-set (`.mrs`) back into a list of domains or subnets, with search and export."
        case .clientHeaders:
            "Requests your subscription with the headers of different clients (Happ, Clash family, sing-box…) and shows what the server returns to each, grouped by client type."
        }
    }

    /// Tools with a fully-implemented, tested screen. Exhaustive on purpose: a
    /// new tool must answer "is this done?" at the compiler, not ship silently
    /// as a placeholder.
    var isImplemented: Bool {
        switch self {
        case .happRouting, .happDecrypt, .incyLink, .subscription, .sniCheck, .realityScanner,
             .clientHeaders, .geoData, .xrayCheck, .mrsViewer:
            return true
        }
    }
}

/// Groups the VPN tools in the landing list.
struct VPNSection: Identifiable {
    let id: String
    let title: String
    let tools: [VPNTool]
}

enum VPNCatalog {
    static let sections: [VPNSection] = [
        VPNSection(id: "links", title: "Links and subscriptions",
                   tools: [.happRouting, .subscription, .happDecrypt, .incyLink]),
        VPNSection(id: "server", title: "Server checks",
                   tools: [.sniCheck, .realityScanner, .xrayCheck]),
        VPNSection(id: "data", title: "Lists and data",
                   tools: [.geoData, .mrsViewer, .clientHeaders]),
    ]
}
