import Foundation

public enum CensorshipVerdict: String, Sendable, Codable {
    case clean          // no restriction observed
    case restricted     // restriction observed
    case inconclusive   // couldn't determine (e.g. control also failed)
}

public struct CensorshipFinding: Sendable {
    public let verdict: CensorshipVerdict
    public let headline: String
    public let detail: String
    public let evidence: [String]

    public init(verdict: CensorshipVerdict, headline: String, detail: String, evidence: [String]) {
        self.verdict = verdict
        self.headline = headline
        self.detail = detail
        self.evidence = evidence
    }
}

/// Client-side detection of local ISP restrictions, always comparing the user's
/// connection against a trusted control (OONI-style). Pure diagnostics.
public struct CensorshipChecks: Sendable {
    public init() {}

    // Canary resources (transparency test targets; not circumvention).
    public static let blockedCanaries = ["rutracker.org", "x.com", "www.tor-project.org"]
    public static let whitelistAnchors = ["gosuslugi.ru", "yandex.ru", "vk.ru", "sberbank.ru", "mail.ru"]
    public static let foreignControls = ["example.com", "wikipedia.org", "www.google.com"]
    static let blockPageMarkers = ["access restricted", "access restricted", "Roskomnadzor",
                                   "Federal Law 149-FZ", "blocked", "banned", "unified registry"]

    // MARK: 1. DNS spoofing / substitution

    public func checkDNSSpoofing(domain: String = "rutracker.org") async -> CensorshipFinding {
        // IPv4 on purpose: compared against DoH A records below, so both sides
        // must be A records for the spoofing check to be apples-to-apples.
        let systemIPs = (try? await HostResolver.resolve(host: domain, family: .ipv4).map(\.ipString)) ?? []
        let dohIPs = (try? await DoHClient().resolveA(domain)) ?? []

        var evidence = ["System DNS: \(systemIPs.isEmpty ? "no response" : systemIPs.joined(separator: ", "))",
                        "DoH 1.1.1.1: \(dohIPs.isEmpty ? "no response" : dohIPs.joined(separator: ", "))"]

        if dohIPs.isEmpty {
            return CensorshipFinding(verdict: .inconclusive, headline: "Couldn't check",
                                     detail: "The reference resolver (DoH) is unavailable.", evidence: evidence)
        }
        if systemIPs.isEmpty {
            return CensorshipFinding(verdict: .restricted, headline: "Domain doesn't resolve via provider",
                                     detail: "Your DNS returned no address while the reference one did — a DNS-level block is likely.",
                                     evidence: evidence)
        }
        let systemSet = Set(systemIPs), dohSet = Set(dohIPs)
        if systemSet.isDisjoint(with: dohSet) {
            let privateInjected = systemIPs.contains { DNSClient.isPrivateOrLoopback($0) }
            evidence.append(privateInjected ? "The system response points to a private network — injection." : "The responses differ completely.")
            return CensorshipFinding(verdict: .restricted, headline: "Looks like DNS spoofing",
                                     detail: "The provider's resolver returned a different address than the reference one. This is a typical sign of DNS spoofing.",
                                     evidence: evidence)
        }
        return CensorshipFinding(verdict: .clean, headline: "No DNS spoofing detected",
                                 detail: "The provider's and reference responses match.", evidence: evidence)
    }

    // MARK: 2. IP blocking

    public func checkIPBlocking(domain: String = "x.com") async -> CensorshipFinding {
        let dohIPs = (try? await DoHClient().resolveA(domain)) ?? []
        guard let targetIP = dohIPs.first else {
            return CensorshipFinding(verdict: .inconclusive, headline: "Couldn't check",
                                     detail: "Couldn't get the domain's real address.", evidence: [])
        }
        let scanner = PortScanner()
        let target = await scanner.check(host: targetIP, port: 443, timeout: 4)
        let control = await scanner.check(host: "1.1.1.1", port: 443, timeout: 4)

        let evidence = ["Target \(targetIP):443 — \(target.isOpen ? "reachable" : "unreachable")",
                        "Control 1.1.1.1:443 — \(control.isOpen ? "reachable" : "unreachable")"]

        if !control.isOpen {
            return CensorshipFinding(verdict: .inconclusive, headline: "No connection",
                                     detail: "Even the control address is unreachable — check your connection.", evidence: evidence)
        }
        if !target.isOpen {
            return CensorshipFinding(verdict: .restricted, headline: "IP address is blocked",
                                     detail: "A direct connection to the domain's real address doesn't go through, even though the control address is reachable.",
                                     evidence: evidence)
        }
        return CensorshipFinding(verdict: .clean, headline: "No IP block",
                                 detail: "The domain's real address is reachable directly.", evidence: evidence)
    }

    // MARK: 3. SNI / TLS blocking (RST injection or drop)

    public func checkSNIBlocking(blockedDomain: String = "www.tor-project.org") async -> CensorshipFinding {
        let dohIPs = (try? await DoHClient().resolveA(blockedDomain)) ?? []
        guard let ip = dohIPs.first else {
            return CensorshipFinding(verdict: .inconclusive, headline: "Couldn't check",
                                     detail: "Couldn't get the domain's address.", evidence: [])
        }
        // Same IP, two SNIs: the blocked name vs a benign control name.
        let blocked = await tlsSucceeds(ip: ip, sni: blockedDomain)
        let control = await tlsSucceeds(ip: ip, sni: "example.com")

        let evidence = ["TLS to \(ip) with SNI=\(blockedDomain): \(blocked ? "success" : "reset/timeout")",
                        "TLS to \(ip) with SNI=example.com: \(control ? "success" : "reset/timeout")"]

        if !blocked && control {
            return CensorshipFinding(verdict: .restricted, headline: "SNI-based block",
                                     detail: "A connection to the same IP is cut off only when the TLS name is a “restricted” one — the network filters by SNI (DPI).",
                                     evidence: evidence)
        }
        if !blocked && !control {
            return CensorshipFinding(verdict: .inconclusive, headline: "Host unreachable",
                                     detail: "Both connections failed — likely an IP block or the host is unreachable.", evidence: evidence)
        }
        return CensorshipFinding(verdict: .clean, headline: "No SNI block",
                                 detail: "The TLS connection with the “restricted” name goes through normally.", evidence: evidence)
    }

    // MARK: 4. HTTP block page injection

    public func checkHTTPBlockPage(domain: String = "rutracker.org") async -> CensorshipFinding {
        guard let body = await httpBody(domain: domain) else {
            return CensorshipFinding(verdict: .inconclusive, headline: "No response",
                                     detail: "HTTP request returned no body.", evidence: ["GET http://\(domain)"])
        }
        let lower = body.lowercased()
        let hit = Self.blockPageMarkers.first { lower.contains($0) }
        if let hit {
            return CensorshipFinding(verdict: .restricted, headline: "Block page",
                                     detail: "The provider replaced the response with a block page.",
                                     evidence: ["Marker found: “\(hit)”", "GET http://\(domain)"])
        }
        return CensorshipFinding(verdict: .clean, headline: "No block page detected",
                                 detail: "HTTP response contains no block-page markers.", evidence: ["GET http://\(domain)"])
    }

    // MARK: 5. Whitelist mode

    public func checkWhitelistMode() async -> CensorshipFinding {
        var anchorOK = 0, controlOK = 0
        var evidence: [String] = []
        for host in Self.whitelistAnchors {
            let ok = await PortScanner().check(host: host, port: 443, timeout: 4).isOpen
            if ok { anchorOK += 1 }
        }
        for host in Self.foreignControls {
            let ok = await PortScanner().check(host: host, port: 443, timeout: 4).isOpen
            if ok { controlOK += 1 }
        }
        // IP-layer control removes DNS from the equation.
        let ipControl = await PortScanner().check(host: "1.1.1.1", port: 443, timeout: 4).isOpen

        evidence.append("Reachable from whitelist: \(anchorOK)/\(Self.whitelistAnchors.count)")
        evidence.append("Foreign controls reachable: \(controlOK)/\(Self.foreignControls.count)")
        evidence.append("Direct IP 1.1.1.1:443: \(ipControl ? "reachable" : "unreachable")")

        if anchorOK >= 2 && controlOK == 0 && !ipControl {
            return CensorshipFinding(verdict: .restricted, headline: "Whitelist mode",
                                     detail: "Only “allowed” resources are reachable, everything else is blocked — looks like whitelist mode (regional shutdown).",
                                     evidence: evidence)
        }
        if controlOK == 0 && anchorOK == 0 {
            return CensorshipFinding(verdict: .inconclusive, headline: "No connection",
                                     detail: "Nothing is reachable — check your connection.", evidence: evidence)
        }
        return CensorshipFinding(verdict: .clean, headline: "No whitelist",
                                 detail: "Foreign resources are as reachable as local ones.", evidence: evidence)
    }

    // MARK: 6. Siberian block (stateful TLS-flood throttle)

    public func checkSiberianBlock(host: String = "www.tor-project.org", bursts: Int = 30) async -> CensorshipFinding {
        let dohIPs = (try? await DoHClient().resolveA(host)) ?? []
        guard let ip = dohIPs.first else {
            return CensorshipFinding(verdict: .inconclusive, headline: "Couldn't check",
                                     detail: "Couldn't get the address.", evidence: [])
        }
        // Fire many parallel TLS handshakes to the same host in a short window.
        let results = await withTaskGroup(of: Bool.self) { group -> [Bool] in
            for _ in 0..<bursts {
                group.addTask { await self.tlsSucceeds(ip: ip, sni: host, timeout: 6) }
            }
            var r: [Bool] = []
            for await ok in group { r.append(ok) }
            return r
        }
        let ok = results.filter { $0 }.count
        let failed = results.count - ok
        let evidence = ["Parallel TLS: \(results.count)", "Success: \(ok)", "Dropped: \(failed)"]

        // A stateful flood throttle lets the first handshakes through, then drops the rest.
        if ok >= 3 && failed >= max(5, bursts / 3) {
            return CensorshipFinding(verdict: .restricted, headline: "Looks like a “Siberian” block",
                                     detail: "Some parallel TLS connections to a single host drop — characteristic of DPI throttling by number of TLS sessions. Usually resets after ~2 minutes.",
                                     evidence: evidence)
        }
        if ok == 0 {
            return CensorshipFinding(verdict: .inconclusive, headline: "Host unreachable",
                                     detail: "No connection went through — likely another block or the host is unreachable.", evidence: evidence)
        }
        return CensorshipFinding(verdict: .clean, headline: "No TLS throttling detected",
                                 detail: "All parallel connections went through fine.", evidence: evidence)
    }

    // MARK: Helpers

    private func tlsSucceeds(ip: String, sni: String, timeout: TimeInterval = 5) async -> Bool {
        do {
            _ = try await TLSInspector().inspect(host: ip, port: 443, serverName: sni,
                                                 alpnProtocols: ["h2", "http/1.1"], timeout: timeout)
            return true
        } catch {
            return false
        }
    }

    private func httpBody(domain: String, timeout: TimeInterval = 6) async -> String? {
        guard let url = URL(string: "http://\(domain)/") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let session = URLSession(configuration: config)
        guard let (data, _) = try? await session.data(for: request) else { return nil }
        return String(decoding: data.prefix(20_000), as: UTF8.self)
    }
}
