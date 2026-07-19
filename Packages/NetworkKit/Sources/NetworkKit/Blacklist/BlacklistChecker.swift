import Foundation

public struct BlacklistProvider: Sendable, Hashable, Codable, Identifiable {
    public var id: String { zone }
    public let name: String
    public let zone: String
    public init(name: String, zone: String) { self.name = name; self.zone = zone }

    public static let all: [BlacklistProvider] = [
        .init(name: "Spamhaus ZEN", zone: "zen.spamhaus.org"),
        .init(name: "SpamCop", zone: "bl.spamcop.net"),
        .init(name: "Barracuda", zone: "b.barracudacentral.org"),
        .init(name: "SORBS", zone: "dnsbl.sorbs.net"),
        .init(name: "UCEPROTECT-1", zone: "dnsbl-1.uceprotect.net"),
        .init(name: "PSBL", zone: "psbl.surriel.com"),
        .init(name: "S5H", zone: "all.s5h.net"),
        .init(name: "Mailspike", zone: "bl.mailspike.net")
    ]
}

public struct BlacklistEntry: Sendable, Hashable, Codable, Identifiable {
    public var id: String { provider.id }
    public let provider: BlacklistProvider
    public enum Status: String, Sendable, Codable { case listed, clean, error }
    public let status: Status
    public let codes: [String]    // returned 127.0.0.x codes when listed
    public let latencyMillis: Double
}

public struct BlacklistReport: Sendable {
    public let ip: String
    public let entries: [BlacklistEntry]
    public var listedCount: Int { entries.filter { $0.status == .listed }.count }
    public var checkedCount: Int { entries.filter { $0.status != .error }.count }
}

/// Checks an IPv4 address against multiple DNSBLs using the system resolver
/// (important, because several DNSBLs refuse queries from public resolvers).
public struct BlacklistChecker: Sendable {
    public init() {}

    public func check(
        ip: String,
        providers: [BlacklistProvider] = BlacklistProvider.all
    ) async -> BlacklistReport {
        let trimmed = ip.trimmingCharacters(in: .whitespaces)
        guard let reversed = Self.reversedIPv4(trimmed) else {
            return BlacklistReport(ip: trimmed, entries: [])
        }

        let entries = await withTaskGroup(of: BlacklistEntry.self) { group in
            for provider in providers {
                group.addTask {
                    let query = "\(reversed).\(provider.zone)"
                    let start = MonoClock.nanos()
                    do {
                        let results = try await HostResolver.resolve(host: query, family: .ipv4)
                        let codes = results.map(\.ipString).filter { $0.hasPrefix("127.") }
                        // A 127.x answer means listed; anything else treat as clean.
                        let status: BlacklistEntry.Status = codes.isEmpty ? .clean : .listed
                        return BlacklistEntry(provider: provider, status: status, codes: codes,
                                              latencyMillis: MonoClock.millisSince(start))
                    } catch {
                        // NXDOMAIN (the common case) = not listed.
                        let clean = Self.isNegativeAnswer(error)
                        return BlacklistEntry(provider: provider,
                                              status: clean ? .clean : .error,
                                              codes: [], latencyMillis: MonoClock.millisSince(start))
                    }
                }
            }
            var out: [BlacklistEntry] = []
            for await e in group { out.append(e) }
            return providers.compactMap { p in out.first { $0.provider.id == p.id } }
        }

        return BlacklistReport(ip: trimmed, entries: entries)
    }

    static func reversedIPv4(_ ip: String) -> String? {
        let parts = ip.split(separator: ".")
        guard parts.count == 4, parts.allSatisfy({ Int($0).map { (0...255).contains($0) } ?? false }) else { return nil }
        return parts.reversed().joined(separator: ".")
    }

    private static func isNegativeAnswer(_ error: Error) -> Bool {
        guard let netErr = error as? NetworkError,
              case .resolutionFailed(_, let reason) = netErr else { return false }
        let r = reason.lowercased()
        return r.contains("not known") || r.contains("no address") || r.contains("nodename")
            || r.contains("nxdomain") || r.contains("name does not")
    }
}
