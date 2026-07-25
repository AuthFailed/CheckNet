import Foundation

/// Looks up published version tags for a VPN client from its GitHub releases, so
/// the client-header test can offer real versions to spoof instead of a
/// hard-coded guess. Open-source clients only — closed ones (Happ, Shadowrocket,
/// V2Box, Streisand) have no public release feed and stay manual-entry.
public enum ClientReleaseIndex {
    /// Client id (see `SubscriptionUserAgents`) → `owner/repo`. Also matched by
    /// normalized product name so custom rows can resolve too.
    public static let repos: [String: String] = [
        "v2rayng":   "2dust/v2rayNG",
        "singbox":   "SagerNet/sing-box",
        "clashmeta": "clash-verge-rev/clash-verge-rev",
        "hiddify":   "hiddify/hiddify-app",
        "nekobox":   "MatsuriDayo/NekoBoxForAndroid",
        "karing":    "KaringX/karing",
        "mihomo":    "MetaCubeX/mihomo",
        "flclash":   "chen08209/FlClash",
    ]

    /// Product name (as it appears before `/` in a UA) → the same repo map.
    private static let byProduct: [String: String] = [
        "v2rayng": "2dust/v2rayNG",
        "sing-box": "SagerNet/sing-box",
        "clash-verge": "clash-verge-rev/clash-verge-rev",
        "clash-meta": "clash-verge-rev/clash-verge-rev",
        "hiddify": "hiddify/hiddify-app",
        "nekobox": "MatsuriDayo/NekoBoxForAndroid",
        "karing": "KaringX/karing",
        "mihomo": "MetaCubeX/mihomo",
        "flclash": "chen08209/FlClash",
    ]

    /// Resolves a repo from a client id or a free-typed product name.
    public static func repo(clientID: String? = nil, product: String? = nil) -> String? {
        if let clientID, let r = repos[clientID.lowercased()] { return r }
        if let product {
            let key = product.lowercased().trimmingCharacters(in: .whitespaces)
            if let r = byProduct[key] { return r }
        }
        return nil
    }

    /// Parses a GitHub `/releases` JSON array into version strings, newest first,
    /// dropping drafts and the leading `v`.
    public static func parseVersions(_ data: Data) -> [String] {
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        var out: [String] = []
        var seen = Set<String>()
        for rel in arr {
            if rel["draft"] as? Bool == true { continue }
            guard let tag = rel["tag_name"] as? String else { continue }
            let version = tag.hasPrefix("v") || tag.hasPrefix("V") ? String(tag.dropFirst()) : tag
            let trimmed = version.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else { continue }
            seen.insert(trimmed)
            out.append(trimmed)
        }
        return out
    }

    public enum ReleaseError: Error, Sendable { case badRepo, http(Int), empty }

    /// Fetches the most recent release versions for `owner/repo`.
    public static func versions(repo: String, limit: Int = 20, timeout: TimeInterval = 12) async throws -> [String] {
        guard repo.contains("/"),
              let url = URL(string: "https://api.github.com/repos/\(repo)/releases?per_page=\(limit)") else {
            throw ReleaseError.badRepo
        }
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("CheckNet", forHTTPHeaderField: "User-Agent")   // GitHub requires a UA.
        req.timeoutInterval = timeout

        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw ReleaseError.http(http.statusCode)
        }
        let versions = parseVersions(data)
        if versions.isEmpty { throw ReleaseError.empty }
        return versions
    }
}
