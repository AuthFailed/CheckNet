import SwiftUI

/// Every diagnostic tool the app offers. `implemented` gates whether a real
/// screen is wired up yet; the rest show a polished "coming soon" scaffold.
enum Tool: String, CaseIterable, Identifiable, Codable {
    // Reachability
    case ping, traceroute, mtr, portScan, tlsInspector
    // DNS
    case dns, dnsCompare, dnsTamper, reverseDns
    // Discovery
    case networkBrowser, ipScanner, bonjour, wakeOnLan
    // Info
    case interfaces, hostToIP, ipLocation, whois, blacklist
    // Performance
    case speedTest, bufferbloat, mtuDiscovery
    // Wi-Fi
    case wifiAnalysis, currentWiFi
    // Advanced
    case worldPing, cgnatDetect, monitoring

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ping: return "Ping"
        case .traceroute: return "Traceroute"
        case .mtr: return "MTR"
        case .portScan: return "Port check"
        case .tlsInspector: return "TLS inspector"
        case .dns: return "DNS (nslookup)"
        case .dnsCompare: return "Resolver comparison"
        case .dnsTamper: return "DNS spoofing detection"
        case .reverseDns: return "Reverse DNS"
        case .networkBrowser: return "Network overview"
        case .ipScanner: return "IP range scanner"
        case .bonjour: return "Bonjour / mDNS"
        case .wakeOnLan: return "Wake-on-LAN"
        case .interfaces: return "Network interfaces"
        case .hostToIP: return "Host → IP"
        case .ipLocation: return "IP geolocation"
        case .whois: return "Domain Whois"
        case .blacklist: return "Blacklist check"
        case .speedTest: return "Speed test"
        case .bufferbloat: return "Bufferbloat"
        case .mtuDiscovery: return "MTU discovery"
        case .wifiAnalysis: return "Wi-Fi analysis"
        case .currentWiFi: return "Current Wi-Fi network"
        case .worldPing: return "World Ping"
        case .cgnatDetect: return "CGNAT / Double NAT"
        case .monitoring: return "Host monitoring"
        }
    }

    var subtitle: String {
        switch self {
        case .ping: return "ICMP · latency, loss, jitter"
        case .traceroute: return "Path to host by hops"
        case .mtr: return "Traceroute + continuous ping"
        case .portScan: return "TCP connect across ports"
        case .tlsInspector: return "Certificates, TLS, ALPN"
        case .dns: return "All record types, latency"
        case .dnsCompare: return "Different resolvers side by side"
        case .dnsTamper: return "DNS spoofing and censorship"
        case .reverseDns: return "IP → hostname (PTR)"
        case .networkBrowser: return "Devices on your network"
        case .ipScanner: return "Live hosts in range"
        case .bonjour: return "mDNS services nearby"
        case .wakeOnLan: return "Wake a device by MAC"
        case .interfaces: return "IP, mask, MAC, MTU"
        case .hostToIP: return "Name-to-address resolution"
        case .ipLocation: return "Country, city, ASN"
        case .whois: return "Registrar, dates, NS"
        case .blacklist: return "IP on DNSBL lists"
        case .speedTest: return "Download/upload speed"
        case .bufferbloat: return "Latency increase under load"
        case .mtuDiscovery: return "Maximum packet size"
        case .wifiAnalysis: return "RSSI, channel, roaming"
        case .currentWiFi: return "SSID, BSSID, security · on Mac also signal and channel"
        case .worldPing: return "Availability from different locations"
        case .cgnatDetect: return "NAT type and external IP"
        case .monitoring: return "Background uptime monitor"
        }
    }

    var systemImage: String {
        switch self {
        case .ping: return "dot.radiowaves.left.and.right"
        case .traceroute: return "point.topleft.down.to.point.bottomright.curvepath"
        case .mtr: return "chart.line.uptrend.xyaxis"
        case .portScan: return "square.grid.3x3.middle.filled"
        case .tlsInspector: return "lock.shield"
        case .dns: return "magnifyingglass"
        case .dnsCompare: return "arrow.left.arrow.right"
        case .dnsTamper: return "exclamationmark.shield"
        case .reverseDns: return "arrow.uturn.backward"
        case .networkBrowser: return "rectangle.connected.to.line.below"
        case .ipScanner: return "barcode.viewfinder"
        case .bonjour: return "bonjour"
        case .wakeOnLan: return "power"
        case .interfaces: return "network"
        case .hostToIP: return "arrow.right.circle"
        case .ipLocation: return "mappin.and.ellipse"
        case .whois: return "doc.text.magnifyingglass"
        case .blacklist: return "hand.raised.slash"
        case .speedTest: return "gauge.with.dots.needle.67percent"
        case .bufferbloat: return "waveform.path.ecg"
        case .mtuDiscovery: return "ruler"
        case .wifiAnalysis: return "wifi"
        case .currentWiFi: return "wifi"
        case .worldPing: return "globe"
        case .cgnatDetect: return "arrow.triangle.branch"
        case .monitoring: return "bell.badge"
        }
    }

    /// Search synonyms — the names people actually type, in both languages, so
    /// "latency", "nslookup", "dig", "ping", "ports", "certificate" all land on
    /// the right tool even though none of them is in its title.
    var keywords: [String] {
        switch self {
        case .ping: return ["ping", "latency", "loss", "jitter", "icmp"]
        case .traceroute: return ["traceroute", "tracert", "route", "hops"]
        case .mtr: return ["mtr", "my traceroute", "winmtr", "traceroute", "per-hop loss"]
        case .portScan: return ["port", "ports", "scan", "tcp", "open ports"]
        case .tlsInspector: return ["tls", "ssl", "certificate", "cert", "https", "handshake", "cipher"]
        case .dns: return ["dns", "nslookup", "dig", "domain", "record", "a", "aaaa", "mx", "txt", "resolve"]
        case .dnsCompare: return ["dns", "resolvers", "compare", "doh", "1.1.1.1", "8.8.8.8"]
        case .dnsTamper: return ["dns", "spoof", "tamper", "dns monitoring"]
        case .reverseDns: return ["reverse dns", "ptr", "rdns", "name by ip"]
        case .networkBrowser: return ["network", "devices", "browse", "mac", "vendor", "arp"]
        case .ipScanner: return ["ip", "scan", "range", "cidr", "hosts", "network"]
        case .bonjour: return ["bonjour", "mdns", "zeroconf", "services", "airplay", "chromecast"]
        case .wakeOnLan: return ["wake on lan", "wol", "magic packet", "wake", "power on", "mac"]
        case .interfaces: return ["interface", "adapter", "ip", "netmask", "gateway"]
        case .hostToIP: return ["host", "ip", "resolve", "domain to ip", "a record"]
        case .ipLocation: return ["geo", "geolocation", "location", "country", "city", "asn"]
        case .whois: return ["whois", "domain", "registrar", "owner", "registration date"]
        case .blacklist: return ["blacklist", "dnsbl", "rbl", "spam", "reputation"]
        case .speedTest: return ["speed", "iperf", "speedtest", "download", "upload"]
        case .bufferbloat: return ["bufferbloat", "buffer", "latency under load"]
        case .mtuDiscovery: return ["mtu", "fragmentation", "pmtud", "packet size"]
        case .wifiAnalysis: return ["wifi", "channels", "interference"]
        case .currentWiFi: return ["wifi", "network", "ssid", "bssid", "security", "signal", "rssi", "channel"]
        case .worldPing: return ["world ping", "from multiple locations", "global"]
        case .cgnatDetect: return ["cgnat", "nat", "shared ip", "carrier grade", "double nat"]
        case .monitoring: return ["monitoring", "continuous", "notifications", "alerts", "downtime"]
        }
    }

    /// Everything a query is matched against: title, subtitle, synonyms and the
    /// ⓘ description.
    func matches(_ query: String) -> Bool {
        let haystack = ([title, subtitle, info] + keywords).joined(separator: "\n")
        return haystack.localizedCaseInsensitiveContains(query)
    }

    /// A short "what & why" description shown behind the ⓘ button.
    var info: String {
        switch self {
        case .ping:
            return "Sends ICMP echoes to the host and measures response time, packet loss, and jitter. Helps you tell whether the node is reachable and the connection to it is stable."
        case .traceroute:
            return "Shows the packet route to the host step by step (hops) and the latency at each. Helps find which network segment has problems."
        case .mtr:
            return "Combines traceroute and continuous ping: constantly polls each hop and accumulates loss and latency stats. Like WinMTR — handy for catching an unstable segment."
        case .portScan:
            return "Checks which TCP ports are open on a host. Helps find out which services are available. Scanning others' hosts may be treated as an unfriendly action."
        case .tlsInspector:
            return "Opens a TLS connection and shows the certificate, trust chain, protocol version, and ALPN. Helps verify HTTPS security and correct setup."
        case .dns:
            return "Queries DNS for all record types of a domain (A, AAAA, MX, TXT, etc.) and shows resolver latency. Basic domain-name diagnostics."
        case .dnsCompare:
            return "Queries the same domain from several DNS resolvers and compares the responses side by side. Helps spot spoofing or discrepancies."
        case .dnsTamper:
            return "Compares your DNS response with a trusted one and looks for signs of spoofing or censorship. Moved to the “Blocks” tab."
        case .reverseDns:
            return "Finds the domain name associated with an IP address (PTR record). Helps identify the address owner."
        case .networkBrowser:
            return "Finds devices on your local network and their addresses. Helps you see what's connected to your Wi-Fi."
        case .ipScanner:
            return "Iterates over a range of IP addresses and finds live hosts. Useful for inventorying your own network. Scanning others' networks may be considered unfriendly."
        case .bonjour:
            return "Finds Bonjour/mDNS services nearby (printers, AirPlay, speakers, etc.). Shows what advertises itself on your network."
        case .wakeOnLan:
            return "Sends a “magic packet” to a MAC address to remotely wake a device on the local network."
        case .interfaces:
            return "Shows the device's network interfaces: IP, mask, MAC, and MTU. Basic info about your connection."
        case .hostToIP:
            return "Converts a domain name to an IP address (and vice versa). The simplest DNS check."
        case .ipLocation:
            return "Estimates the likely country, city and network (ASN and operator) for an IP or domain, with links to bgp.tools, Hurricane Electric and PeeringDB. The request goes to an external geolocation service."
        case .whois:
            return "Requests domain registration data: registrar, dates, name servers. Helps find out who owns the domain."
        case .blacklist:
            return "Checks whether an IP is listed in email blacklists (DNSBL). Useful if your mail ends up in spam."
        case .speedTest:
            return "Measures download and upload speed via iperf3 servers or HTTP. Shows the real bandwidth of your connection."
        case .bufferbloat:
            return "Measures latency at idle and under full load (download and upload), showing the increase and an A–F grade. It’s the rise in latency under load that breaks calls and games even on a fast connection."
        case .mtuDiscovery:
            return "Finds the maximum packet size that passes without fragmentation (Path MTU). Helps diagnose drops and stalled connections."
        case .wifiAnalysis:
            return "Wi-Fi analysis: signal strength, channel, roaming. Limited by iOS policies."
        case .currentWiFi:
            return "Shows the Wi-Fi network the device is connected to right now: name (SSID), the access point's BSSID, and security type. On Mac, also signal level, channel, bandwidth, speed, and standard. Nearby networks aren't scanned — use \"Wi-Fi Analysis\" for that."
        case .worldPing:
            return "Checks a host’s reachability from nodes around the world — ping, HTTP, TCP, DNS or UDP, with a choice of countries. You see where the resource is reachable and where it isn’t. The check runs through an external service."
        case .cgnatDetect:
            return "Determines NAT type and your external IP via STUN. Helps you tell whether you're behind CGNAT (a shared provider address)."
        case .monitoring:
            return "Background host-availability monitor: pings periodically and keeps an uptime history."
        }
    }

    /// Tools whose activity could be seen as intrusive on foreign networks
    /// (scanning). Gated behind a one-time consent prompt.
    var isSensitive: Bool {
        switch self {
        case .portScan, .ipScanner:
            return true
        default:
            return false
        }
    }

    /// Tools that now live in the Blocking tab and must not appear in the
    /// main catalog or search (kept routable for deep links).
    var isCensorshipCheck: Bool { self == .dnsTamper }

    /// Tools with a fully-implemented, tested screen.
    ///
    /// An exhaustive switch on purpose: `default: return false` meant a new tool
    /// silently shipped as a placeholder. Now the compiler makes adding a case a
    /// deliberate answer to "is this done?".
    var isImplemented: Bool {
        switch self {
        case .ping, .traceroute, .mtr, .dns, .dnsCompare, .dnsTamper, .portScan, .tlsInspector,
             .hostToIP, .reverseDns, .interfaces, .whois, .blacklist, .wakeOnLan,
             .mtuDiscovery, .ipScanner, .bonjour, .cgnatDetect, .monitoring, .networkBrowser,
             .speedTest, .bufferbloat, .ipLocation, .worldPing, .currentWiFi:
            // Current-network identity (SSID/BSSID/security) is available on iOS
            // too now that Access Wi-Fi Information is signed; the full RF detail
            // is macOS-only inside the same screen.
            return true
        case .wifiAnalysis:
            // A scan of neighbouring networks — iOS gives apps no such API.
            #if os(macOS)
            return true
            #else
            return false
            #endif
        }
    }

    /// Why an unimplemented tool is not here — the honest version, not "soon".
    enum Unavailable {
        /// The engine is planned; it will arrive in a build.
        case inDevelopment(String)
        /// It cannot exist on this platform, and no amount of waiting changes
        /// that. iOS does not hand RSSI to apps; some checks need a paid API.
        case platformLimit(String)

        var headline: LocalizedStringKey {
            switch self {
            case .inDevelopment: "In development"
            case .platformLimit: "Unavailable on this platform"
            }
        }
        var icon: String {
            switch self {
            case .inDevelopment: "hammer"
            case .platformLimit: "hand.raised.slash"
            }
        }
        var detail: String {
            switch self {
            case .inDevelopment(let s), .platformLimit(let s): s
            }
        }
    }

    /// Present only for tools that are not implemented.
    var unavailable: Unavailable? {
        switch self {
        case .wifiAnalysis:
            return .platformLimit("iOS doesn’t give apps Wi-Fi channel or neighboring-network data — it’s only available in the Mac version (CoreWLAN).")
        default:
            return nil
        }
    }
}

/// A category grouping in the catalog.
struct ToolSection: Identifiable {
    let id: String
    let title: String
    let tools: [Tool]
}

enum ToolCatalog {
    static let sections: [ToolSection] = [
        ToolSection(id: "reach", title: "Availability", tools: [.ping, .traceroute, .mtr, .portScan, .tlsInspector]),
        ToolSection(id: "dns", title: "DNS", tools: [.dns, .dnsCompare, .reverseDns]),
        ToolSection(id: "discovery", title: "Discovery", tools: [.networkBrowser, .ipScanner, .bonjour, .wakeOnLan]),
        ToolSection(id: "info", title: "Info", tools: [.interfaces, .hostToIP, .ipLocation, .whois, .blacklist]),
        ToolSection(id: "perf", title: "Performance", tools: [.speedTest, .bufferbloat, .mtuDiscovery]),
        ToolSection(id: "wifi", title: "Wi-Fi", tools: [.currentWiFi, .wifiAnalysis]),
        ToolSection(id: "advanced", title: "Advanced", tools: [.worldPing, .cgnatDetect, .monitoring])
    ]

    static func tool(withID id: String) -> Tool? { Tool(rawValue: id) }
}
