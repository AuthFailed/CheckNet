import Foundation

/// Manages the offline MaxMind GeoLite2 databases (City + ASN), taken from the
/// P3TERX/GeoLite.mmdb GitHub releases. The lookup itself is local — no IP is
/// sent anywhere — only the database files are downloaded, and only when the
/// release actually changed.
///
/// `ensureFresh()` is cheap to call before every run: it compares the latest
/// release tag against the one we downloaded and pulls new files only on a
/// change (or when a file is missing). A failed check (offline, GitHub rate
/// limit) leaves the existing databases in place.
public actor GeoLiteDatabase {
    public static let shared = GeoLiteDatabase()

    public enum Kind: String, Sendable, CaseIterable {
        case city = "GeoLite2-City"
        case asn = "GeoLite2-ASN"
    }

    private let directory: URL
    private let tagKey = "checknet.geolite.tag"
    private var readers: [Kind: MMDBReader] = [:]

    init() {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                 in: .userDomainMask, appropriateFor: nil, create: true))
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        directory = base.appendingPathComponent("GeoLite", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: Readers

    /// A reader for `kind`, memory-mapped from the cached file, or nil if the
    /// database hasn't been downloaded yet.
    func reader(_ kind: Kind) -> MMDBReader? {
        if let cached = readers[kind] { return cached }
        let url = fileURL(kind)
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let reader = MMDBReader(data: data) else { return nil }
        readers[kind] = reader
        return reader
    }

    public var isDownloaded: Bool {
        Kind.allCases.contains { FileManager.default.fileExists(atPath: fileURL($0).path) }
    }

    // MARK: Freshness

    /// Compare the latest release tag with what we have and download the City +
    /// ASN databases if it changed or a file is missing.
    @discardableResult
    public func ensureFresh() async -> Bool {
        let stored = UserDefaults.standard.string(forKey: tagKey)
        let filesPresent = Kind.allCases.allSatisfy { FileManager.default.fileExists(atPath: fileURL($0).path) }
        guard let latest = await latestTag() else {
            return filesPresent   // couldn't check — keep whatever we have
        }
        if latest == stored, filesPresent { return true }

        var allOK = true
        for kind in Kind.allCases where await !download(kind) { allOK = false }
        if allOK {
            UserDefaults.standard.set(latest, forKey: tagKey)
            readers.removeAll()   // reload the new files on next access
        }
        return allOK
    }

    private func latestTag() async -> String? {
        guard let url = URL(string: "https://api.github.com/repos/P3TERX/GeoLite.mmdb/releases/latest") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("CheckNet", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 8
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = object["tag_name"] as? String else { return nil }
        return tag
    }

    private func download(_ kind: Kind) async -> Bool {
        // The "latest/download" URL always serves the newest asset.
        guard let url = URL(string: "https://github.com/P3TERX/GeoLite.mmdb/releases/latest/download/\(kind.rawValue).mmdb") else {
            return false
        }
        guard let (temp, response) = try? await URLSession.shared.download(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return false }
        let destination = fileURL(kind)
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.moveItem(at: temp, to: destination)
            return true
        } catch {
            return false
        }
    }

    private func fileURL(_ kind: Kind) -> URL {
        directory.appendingPathComponent("\(kind.rawValue).mmdb")
    }
}
