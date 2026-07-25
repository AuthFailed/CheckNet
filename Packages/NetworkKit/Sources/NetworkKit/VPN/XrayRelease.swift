import Foundation

/// CPU architecture we need an Xray-core macOS build for.
public enum XrayArch: String, Sendable {
    case arm64, x86_64

    public static var current: XrayArch {
        #if arch(arm64)
        .arm64
        #else
        .x86_64
        #endif
    }

    /// The macOS release asset name Xray-core ships for this arch.
    var assetName: String {
        switch self {
        case .arm64: "Xray-macos-arm64-v8a.zip"
        case .x86_64: "Xray-macos-64.zip"
        }
    }
}

/// A downloadable Xray-core macOS build.
public struct XrayAsset: Sendable, Equatable, Hashable {
    public let name: String
    public let url: String
    public let size: Int
    /// URL of the sibling `.dgst` file carrying the checksums.
    public var digestURL: String?

    public var sizeMB: Double { (Double(size) / 1_048_576 * 10).rounded() / 10 }
}

/// One Xray-core release with the asset for the requested architecture.
public struct XrayRelease: Sendable, Equatable, Identifiable, Hashable {
    public var id: String { version }
    public let version: String        // tag, e.g. "v26.7.11"
    public let prerelease: Bool
    public let publishedAt: String
    public let asset: XrayAsset
}

/// Reads the Xray-core release list from GitHub and picks the right macOS asset.
public enum XrayReleaseIndex {
    public static let repo = "XTLS/Xray-core"

    /// Parse a GitHub `/releases` JSON array into releases that have a macOS
    /// build for `arch`. Prereleases are kept — Xray tags every build that way.
    public static func parse(_ data: Data, arch: XrayArch = .current) -> [XrayRelease] {
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        var out: [XrayRelease] = []
        for rel in arr {
            guard let tag = rel["tag_name"] as? String,
                  let assets = rel["assets"] as? [[String: Any]] else { continue }

            var main: XrayAsset?
            var digestByName: [String: String] = [:]
            for a in assets {
                guard let name = a["name"] as? String,
                      let url = a["browser_download_url"] as? String else { continue }
                if name.hasSuffix(".dgst") {
                    digestByName[String(name.dropLast(5))] = url
                } else if name == arch.assetName {
                    main = XrayAsset(name: name, url: url, size: (a["size"] as? Int) ?? 0)
                }
            }
            guard var asset = main else { continue }
            asset.digestURL = digestByName[asset.name]
            out.append(XrayRelease(
                version: tag,
                prerelease: (rel["prerelease"] as? Bool) ?? false,
                publishedAt: (rel["published_at"] as? String) ?? "",
                asset: asset
            ))
        }
        return out
    }

    /// Fetch and parse the latest releases (default 20).
    public static func fetch(arch: XrayArch = .current, limit: Int = 20) async throws -> [XrayRelease] {
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases?per_page=\(limit)")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("CheckNet", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15
        let (data, _) = try await URLSession.shared.data(for: req)
        return parse(data, arch: arch)
    }

    /// The SHA-256 hex for the asset, read from its `.dgst` body. Xray writes a
    /// line like `SHA2-256= <hex>` (label varies), so we take the 64-hex token
    /// on the SHA-256 line.
    public static func sha256(fromDigest text: String) -> String? {
        for line in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let lower = line.lowercased()
            guard lower.contains("256") else { continue }
            let token = line.split(whereSeparator: { " =\t:".contains($0) }).last.map(String.init)
            if let token, token.count == 64, token.allSatisfy(\.isHexDigit) {
                return token.lowercased()
            }
        }
        return nil
    }
}
