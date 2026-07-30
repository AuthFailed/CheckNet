import SwiftUI
import CryptoKit
import Observation
import NetworkKit

/// Manages downloaded Xray-core builds. On **macOS** the user can download,
/// keep and delete several versions; the through-proxy ping runs whichever is
/// selected. On **iOS** a core cannot be downloaded or executed (App Store
/// 2.5.2 + code signing), so the store only surfaces the latest available
/// version for display — the proxy test there uses the native Reality probe.
@Observable
@MainActor
final class XrayCoreStore {
    struct Installed: Identifiable, Hashable {
        var id: String { version }
        let version: String
        let binary: URL
        let size: Int
        var sizeMB: Double { (Double(size) / 1_048_576 * 10).rounded() / 10 }
    }

    struct Download: Equatable {
        let version: String
        var progress: Double        // 0…1
    }

    private(set) var installed: [Installed] = []
    var available: [XrayRelease] = []
    var loadingIndex = false
    var indexError: String?
    var active: Download?
    var installError: String?

    /// Whether this platform can run a downloaded core at all.
    static var isSupported: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    /// The latest version we know of — shown on iOS, and the default download
    /// choice on macOS.
    var latestVersion: String? { available.first?.version }

    init() { refreshInstalled() }

    // MARK: - Index

    func refreshIndex() async {
        loadingIndex = true; indexError = nil
        defer { loadingIndex = false }
        do { available = try await XrayReleaseIndex.fetch() }
        catch { indexError = "Couldn't fetch the version list" }
    }

    // MARK: - Installed set (macOS)

    private var coresDir: URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                 in: .userDomainMask, appropriateFor: nil, create: true))
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("CheckNet/XrayCores", isDirectory: true)
    }

    func refreshInstalled() {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: coresDir, includingPropertiesForKeys: [.fileSizeKey]) else {
            installed = []; return
        }
        installed = entries.compactMap { dir in
            let binary = dir.appendingPathComponent("xray")
            guard fm.isExecutableFile(atPath: binary.path) else { return nil }
            let size = (try? binary.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return Installed(version: dir.lastPathComponent, binary: binary, size: size)
        }
        .sorted { $0.version > $1.version }
    }

    func isInstalled(_ version: String) -> Bool { installed.contains { $0.version == version } }
    func binary(for version: String) -> URL? { installed.first { $0.version == version }?.binary }

    func remove(_ version: String) {
        try? FileManager.default.removeItem(at: coresDir.appendingPathComponent(version, isDirectory: true))
        refreshInstalled()
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: coresDir)
        refreshInstalled()
    }

    // MARK: - Download + install (macOS only)

    func install(_ release: XrayRelease) async {
        #if os(macOS)
        installError = nil
        active = Download(version: release.version, progress: 0)
        defer { active = nil }
        do {
            let zip = try await download(release.asset)
            try await verify(zip, asset: release.asset)
            try unzipCore(zip, version: release.version)
            refreshInstalled()
        } catch {
            installError = (error as? CoreError)?.message ?? "Couldn't install the core"
        }
        #else
        installError = "Core download isn't available on this platform"
        #endif
    }

    enum CoreError: Error { case badURL, http, checksum, noBinary(String)
        var message: String {
            switch self {
            case .badURL: "Invalid core link"
            case .http: "Load error"
            case .checksum: "Checksum mismatch — file is corrupted"
            case .noBinary(let s): "No xray executable found in the archive (\(s))"
            }
        }
    }

    /// Streamed download with progress into a temp file.
    private func download(_ asset: XrayAsset) async throws -> Data {
        guard let url = URL(string: asset.url) else { throw CoreError.badURL }
        let (bytes, response) = try await URLSession.shared.bytes(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 { throw CoreError.http }
        let total = response.expectedContentLength > 0 ? response.expectedContentLength : Int64(asset.size)
        var data = Data(); data.reserveCapacity(Int(max(total, 0)))
        var counter = 0
        for try await byte in bytes {
            data.append(byte)
            counter += 1
            if counter & 0x3FFFF == 0, total > 0 {          // ~every 256 KB
                active?.progress = min(1, Double(data.count) / Double(total))
            }
        }
        active?.progress = 1
        return data
    }

    private func verify(_ data: Data, asset: XrayAsset) async throws {
        guard let digestURL = asset.digestURL, let url = URL(string: digestURL),
              let (body, _) = try? await URLSession.shared.data(from: url),
              let text = String(data: body, encoding: .utf8),
              let expected = XrayReleaseIndex.sha256(fromDigest: text) else {
            return   // no checksum published → skip rather than fail
        }
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actual == expected else { throw CoreError.checksum }
    }

    #if os(macOS)
    private func unzipCore(_ zip: Data, version: String) throws {
        let fm = FileManager.default
        let dir = coresDir.appendingPathComponent(version, isDirectory: true)
        try? fm.removeItem(at: dir)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let zipURL = dir.appendingPathComponent("core.zip")
        try zip.write(to: zipURL)

        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-o", zipURL.path, "xray", "-d", dir.path]
        try unzip.run(); unzip.waitUntilExit()
        try? fm.removeItem(at: zipURL)

        let binary = dir.appendingPathComponent("xray")
        guard fm.fileExists(atPath: binary.path) else { throw CoreError.noBinary(version) }
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
    }
    #endif
}
