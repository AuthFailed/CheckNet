import Foundation

public struct WhoisResult: Sendable, Hashable, Codable {
    public let query: String
    public let server: String
    public let raw: String
    public let fields: [WhoisField]

    public struct WhoisField: Sendable, Hashable, Codable, Identifiable {
        public var id: String { key }
        public let key: String
        public let value: String
    }

    public func value(for key: String) -> String? {
        fields.first { $0.key.caseInsensitiveCompare(key) == .orderedSame }?.value
    }
}

/// A WHOIS client over TCP port 43 with IANA/registrar referral following.
public struct WhoisClient: Sendable {
    public init() {}

    private static let ianaServer = "whois.iana.org"

    public func lookup(_ query: String, timeout: TimeInterval = 8.0) async throws -> WhoisResult {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { throw NetworkError.invalidHost(query) }

        // Start at IANA to discover the authoritative WHOIS server.
        var server = Self.ianaServer
        var raw = try await runQuery(trimmed, server: server, timeout: timeout)

        // Follow up to two referrals (IANA -> registry -> registrar).
        for _ in 0..<2 {
            guard let refer = Self.referral(in: raw), refer != server else { break }
            let referred = (try? await runQuery(trimmed, server: refer, timeout: timeout)) ?? ""
            if referred.isEmpty { break }
            server = refer
            raw = referred
        }

        return WhoisResult(query: trimmed, server: server, raw: raw, fields: Self.parseFields(raw))
    }

    private func runQuery(_ q: String, server: String, timeout: TimeInterval) async throws -> String {
        let endpoint = try await HostResolver.resolveFirst(host: server, port: 43)
        // Verisign .com/.net registry needs the "domain " keyword to return full data.
        let line = (server.contains("verisign") ? "domain \(q)" : q) + "\r\n"
        let payload = [UInt8](line.utf8)
        let response = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[UInt8], Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let bytes = try TCPTransport.requestUntilClose(endpoint: endpoint, query: payload, timeout: timeout)
                    cont.resume(returning: bytes)
                } catch { cont.resume(throwing: error) }
            }
        }
        return String(decoding: response, as: UTF8.self)
    }

    /// Finds the referral server in a WHOIS response.
    private static func referral(in text: String) -> String? {
        let keys = ["refer:", "whois:", "registrar whois server:"]
        for line in text.components(separatedBy: .newlines) {
            let lower = line.lowercased().trimmingCharacters(in: .whitespaces)
            for key in keys where lower.hasPrefix(key) {
                let value = line.drop(while: { $0 != ":" }).dropFirst()
                    .trimmingCharacters(in: .whitespaces)
                if !value.isEmpty { return value }
            }
        }
        return nil
    }

    /// Extracts the most useful fields from a WHOIS response for display.
    private static func parseFields(_ text: String) -> [WhoisResult.WhoisField] {
        let wanted: [(display: String, keys: [String])] = [
            ("Домен", ["domain name", "domain"]),
            ("Регистратор", ["registrar", "registrar name", "sponsoring registrar"]),
            ("Создан", ["creation date", "created", "registered on", "registration time"]),
            ("Обновлён", ["updated date", "last updated", "changed", "last modified"]),
            ("Истекает", ["registry expiry date", "expiry date", "expires", "expiration date", "paid-till"]),
            ("Статус", ["domain status", "status"]),
            ("Организация", ["registrant organization", "org", "organization"]),
            ("Страна", ["registrant country", "country"])
        ]
        var nameServers: [String] = []
        var found: [String: String] = [:]

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).lowercased().trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty else { continue }

            if key == "name server" || key == "nserver" || key == "nameservers" {
                let ns = value.split(separator: " ").first.map(String.init) ?? value
                if !nameServers.contains(ns) { nameServers.append(ns.lowercased()) }
                continue
            }
            for entry in wanted where entry.keys.contains(key) && found[entry.display] == nil {
                found[entry.display] = value
            }
        }

        var fields: [WhoisResult.WhoisField] = []
        for entry in wanted {
            if let v = found[entry.display] {
                fields.append(.init(key: entry.display, value: v))
            }
        }
        if !nameServers.isEmpty {
            fields.append(.init(key: "NS-серверы", value: nameServers.joined(separator: "\n")))
        }
        return fields
    }
}
