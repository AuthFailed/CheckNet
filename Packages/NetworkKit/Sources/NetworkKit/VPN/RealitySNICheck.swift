import Foundation

/// One evaluated aspect of a domain's fitness as a Reality `dest`/SNI.
public struct RealityCriterion: Sendable, Hashable, Codable, Identifiable {
    /// How well the domain meets this particular requirement.
    public enum Grade: String, Sendable, Codable {
        /// Requirement met.
        case pass
        /// Met, but with a caveat worth showing (soft/bonus criteria only).
        case warn
        /// Requirement not met — for a *required* criterion this sinks the verdict.
        case fail
    }

    public var id: String { key }
    /// Stable identifier (also the SF Symbol / localization anchor).
    public let key: String
    /// Short human title (Russian literal, acts as a localization key).
    public let title: String
    public let grade: Grade
    /// One-line explanation of what was actually observed.
    public let detail: String
    /// Required criteria drag the whole verdict to `.fail`; soft ones only `.warn`.
    public let isRequired: Bool

    public init(key: String, title: String, grade: Grade, detail: String, isRequired: Bool) {
        self.key = key
        self.title = title
        self.grade = grade
        self.detail = detail
        self.isRequired = isRequired
    }
}

/// The full verdict on whether a domain can front a Reality inbound.
public struct RealitySNIReport: Sendable, Hashable, Codable {
    public let host: String
    public let port: Int
    public let resolvedIP: String
    public let tlsVersion: String
    public let alpn: String?
    /// Whether the server completes a handshake when we offer *only* X25519.
    public let supportsX25519: Bool
    public let certSubject: String
    public let certIssuer: String
    public let certValid: Bool
    public let certExpiryDays: Int?
    public let sniCoveredByCert: Bool
    public let handshakeMillis: Double
    /// The redirect target host, when the site 3xx-redirected somewhere else.
    public let redirectLocation: String?

    public let criteria: [RealityCriterion]
    /// Overall grade: worst of the required criteria, softened by the bonus ones.
    public let verdict: RealityCriterion.Grade
    public let summary: String
}

/// Checks whether a domain is a good **Reality `dest`/SNI** target.
///
/// Mirrors the acceptance rule of the canonical `XTLS/RealiTLScanner`
/// (TLS 1.3 + ALPN `h2` + a real leaf certificate with subject and issuer) and
/// layers on the `dest`-selection guidance from the REALITY README: X25519
/// support and "the domain is not used for redirection" (a main-domain → `www`
/// redirect is fine). Everything is derived from live TLS/HTTP to the host, so a
/// unit test can confirm it against a real domain — nothing here bypasses DPI;
/// it only helps an operator vet a camouflage target for their own server.
public final class RealitySNICheck: Sendable {
    public init() {}

    public func run(host: String, port: Int = 443, timeout: TimeInterval = 8) async -> RealitySNIReport {
        let trimmed = host
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .split(separator: "/").first.map(String.init) ?? host

        // 1. Main handshake: TLS version, negotiated ALPN, certificate chain, trust.
        let info: TLSInfo
        do {
            info = try await TLSInspector().inspect(
                host: trimmed, port: port,
                alpnProtocols: ["h2", "http/1.1"], timeout: timeout
            )
        } catch {
            return Self.unreachable(host: trimmed, port: port, error: error)
        }

        // 2. In parallel-ish: does it speak TLS 1.3 when we offer *only* X25519,
        //    and does the front page redirect elsewhere?
        async let x25519 = Self.probeX25519(ip: info.resolvedIP, host: trimmed, port: port, timeout: timeout)
        async let redirect = Self.probeRedirect(ip: info.resolvedIP, host: trimmed, port: port, timeout: timeout)
        let supportsX25519 = await x25519
        let redirectLocation = await redirect

        return Self.evaluate(
            host: trimmed, port: port, info: info,
            supportsX25519: supportsX25519, redirectLocation: redirectLocation
        )
    }

    // MARK: - Evaluation

    static func evaluate(
        host: String, port: Int, info: TLSInfo,
        supportsX25519: Bool, redirectLocation: String?
    ) -> RealitySNIReport {
        let leaf = info.leaf
        let subject = (leaf?.subject).flatMap { $0 == "—" ? nil : $0 } ?? ""
        let issuer = (leaf?.issuer).flatMap { $0 == "—" ? nil : $0 } ?? ""
        let certValid = info.trustEvaluationPassed
            && (leaf?.isExpired == false) && (leaf?.isNotYetValid == false)
        let sniCovered = leaf.map { Self.certCovers(host: host, cert: $0) } ?? false

        var criteria: [RealityCriterion] = []

        // --- Required (RealiTLScanner's accept rule) ---
        let isTLS13 = info.negotiatedProtocol == "TLS 1.3"
        criteria.append(RealityCriterion(
            key: "tls13", title: "TLS 1.3",
            grade: isTLS13 ? .pass : .fail,
            detail: isTLS13 ? "TLS 1.3 negotiated." : "Server uses \(info.negotiatedProtocol) — Reality requires TLS 1.3.",
            isRequired: true
        ))

        let isH2 = info.alpn == "h2"
        criteria.append(RealityCriterion(
            key: "h2", title: "HTTP/2 (ALPN h2)",
            grade: isH2 ? .pass : .fail,
            detail: isH2 ? "ALPN negotiated to h2." : "Server didn't negotiate h2 (\(info.alpn ?? "no ALPN")) — HTTP/2 is required.",
            isRequired: true
        ))

        let hasCert = !subject.isEmpty && !issuer.isEmpty
        criteria.append(RealityCriterion(
            key: "cert", title: "Certificate",
            grade: hasCert ? .pass : .fail,
            detail: hasCert ? "Leaf: \(subject), issuer \(issuer)." : "Couldn't read the leaf certificate's subject/issuer.",
            isRequired: true
        ))

        // --- Soft / bonus (REALITY README dest-selection guidance) ---
        criteria.append(RealityCriterion(
            key: "x25519", title: "X25519 key exchange",
            grade: supportsX25519 ? .pass : .warn,
            detail: supportsX25519
                ? "The handshake succeeds when only X25519 is offered."
                : "The server didn't complete the handshake on X25519 alone — Reality relies on this curve.",
            isRequired: false
        ))

        let redirectGrade: RealityCriterion.Grade
        let redirectDetail: String
        if let loc = redirectLocation {
            redirectGrade = .warn
            redirectDetail = "The main page redirects to \(loc) — Reality prefers domains without an external redirect."
        } else {
            redirectGrade = .pass
            redirectDetail = "No external redirect detected from the main page."
        }
        criteria.append(RealityCriterion(
            key: "redirect", title: "No external redirect",
            grade: redirectGrade, detail: redirectDetail, isRequired: false
        ))

        let expiryDays = leaf?.daysUntilExpiry
        criteria.append(RealityCriterion(
            key: "valid", title: "Certificate is trusted and not expired",
            grade: certValid ? .pass : .warn,
            detail: certValid
                ? "The chain passes validation\(expiryDays.map { ", \($0) days until expiry." } ?? ".")"
                : "The chain failed system validation or has expired.",
            isRequired: false
        ))

        criteria.append(RealityCriterion(
            key: "sni", title: "Certificate covers the domain",
            grade: sniCovered ? .pass : .warn,
            detail: sniCovered
                ? "\(host) is present in the certificate's SAN."
                : "\(host) not found in the SAN — the SNI differs from the certificate names.",
            isRequired: false
        ))

        // Verdict: any required failure ⇒ fail; else any soft warning ⇒ warn; else pass.
        let verdict: RealityCriterion.Grade
        if criteria.contains(where: { $0.isRequired && $0.grade == .fail }) {
            verdict = .fail
        } else if criteria.contains(where: { $0.grade == .warn }) {
            verdict = .warn
        } else {
            verdict = .pass
        }

        let summary: String
        switch verdict {
        case .pass: summary = "The domain works as dest/SNI for Reality."
        case .warn: summary = "The domain works, but there are caveats — check the warnings."
        case .fail: summary = "The domain doesn't work as dest/SNI for Reality."
        }

        return RealitySNIReport(
            host: host, port: port, resolvedIP: info.resolvedIP,
            tlsVersion: info.negotiatedProtocol, alpn: info.alpn,
            supportsX25519: supportsX25519,
            certSubject: subject, certIssuer: issuer,
            certValid: certValid, certExpiryDays: expiryDays,
            sniCoveredByCert: sniCovered, handshakeMillis: info.handshakeMillis,
            redirectLocation: redirectLocation,
            criteria: criteria, verdict: verdict, summary: summary
        )
    }

    /// True when `host` matches the certificate's CN or one of its SANs (wildcards included).
    static func certCovers(host: String, cert: TLSCertificate) -> Bool {
        let names = cert.subjectAltNames + [cert.subject]
        let target = host.lowercased()
        for raw in names {
            // Subject strings look like "CN=example.com, O=…" — pull the CN out.
            let candidate = raw.lowercased()
                .split(separator: ",")
                .compactMap { part -> String? in
                    let p = part.trimmingCharacters(in: .whitespaces)
                    if p.hasPrefix("cn=") { return String(p.dropFirst(3)) }
                    if !p.contains("=") { return p }   // bare SAN entry
                    return nil
                }
            for name in candidate where Self.hostMatches(target, pattern: name) { return true }
        }
        return false
    }

    static func hostMatches(_ host: String, pattern: String) -> Bool {
        if pattern == host { return true }
        if pattern.hasPrefix("*.") {
            let suffix = pattern.dropFirst(1)          // ".example.com"
            // A wildcard covers exactly one label: foo.example.com, not a.b.example.com.
            guard host.hasSuffix(suffix) else { return false }
            let head = host.dropLast(suffix.count)
            return !head.isEmpty && !head.contains(".")
        }
        return false
    }

    // MARK: - Probes

    /// Completes a TLS 1.3 handshake offering *only* the X25519 key-exchange
    /// group. Success means the server supports X25519 — the curve Reality's
    /// forged handshake depends on. Runs the blocking raw-socket probe off the
    /// cooperative pool.
    static func probeX25519(ip: String, host: String, port: Int, timeout: TimeInterval) async -> Bool {
        await TLS13GroupProbe.supportsX25519(ip: ip, port: port, serverName: host, timeout: timeout)
    }

    /// Sends a plain HTTP/1.1 `GET /` over TLS and returns the redirect target
    /// host *only if* the page 3xx-redirects to a different registrable host
    /// (a `example.com` → `www.example.com` bounce is treated as no redirect).
    static func probeRedirect(ip: String, host: String, port: Int, timeout: TimeInterval) async -> String? {
        let stream: TLSStream
        do {
            stream = try TLSStream(ip: ip, port: UInt16(port), serverName: host, fingerprint: .noALPN)
            try await stream.open(timeout: timeout)
        } catch {
            return nil   // can't probe ⇒ don't penalize
        }
        defer { stream.close() }

        let request = "GET / HTTP/1.1\r\nHost: \(host)\r\n" +
            "User-Agent: Mozilla/5.0\r\nAccept: */*\r\nConnection: close\r\n\r\n"
        do {
            try await stream.send(Array(request.utf8))
        } catch { return nil }

        var raw = Data()
        while raw.count < 8 * 1024 {
            guard let chunk = try? await stream.receive(timeout: timeout), !chunk.isEmpty else { break }
            raw.append(chunk)
            if let head = Self.headerBlock(raw) { return Self.redirectTarget(head, host: host) }
        }
        if let head = Self.headerBlock(raw) { return Self.redirectTarget(head, host: host) }
        return nil
    }

    static func headerBlock(_ data: Data) -> String? {
        let text = String(decoding: data, as: UTF8.self)
        guard let end = text.range(of: "\r\n\r\n") else { return nil }
        return String(text[..<end.lowerBound])
    }

    /// Returns the redirect host when the response is a 3xx to a *different*
    /// host; otherwise `nil` (no external redirect).
    static func redirectTarget(_ head: String, host: String) -> String? {
        let lines = head.split(separator: "\r\n").map(String.init)
        guard let status = lines.first, status.contains(" 30") else { return nil }
        guard let location = lines.first(where: { $0.lowercased().hasPrefix("location:") })?
            .dropFirst("location:".count).trimmingCharacters(in: .whitespaces) else { return nil }

        guard let target = URL(string: location)?.host?.lowercased() else { return nil }
        let origin = host.lowercased()
        // A bare www. bounce in either direction is acceptable per the README.
        let stripWWW: (String) -> String = { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 }
        if stripWWW(target) == stripWWW(origin) { return nil }
        return target
    }

    // MARK: - Failure

    static func unreachable(host: String, port: Int, error: Error) -> RealitySNIReport {
        let reason = (error as? NetworkError)?.errorDescription ?? error.localizedDescription
        let crit = RealityCriterion(
            key: "reach", title: "Availability",
            grade: .fail, detail: "Couldn't establish a TLS connection: \(reason)", isRequired: true
        )
        return RealitySNIReport(
            host: host, port: port, resolvedIP: "—",
            tlsVersion: "—", alpn: nil, supportsX25519: false,
            certSubject: "", certIssuer: "", certValid: false, certExpiryDays: nil,
            sniCoveredByCert: false, handshakeMillis: 0, redirectLocation: nil,
            criteria: [crit], verdict: .fail,
            summary: "The domain is unreachable over TLS — it can't be checked as a dest."
        )
    }
}
