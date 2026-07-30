import Foundation
import NetworkKit

/// Runs a downloaded Xray core as a short-lived subprocess to serve one
/// through-proxy reachability test, then measures a GET to gstatic through its
/// local SOCKS inbound. macOS only — iOS can neither download nor exec a core.
enum XrayProxyRunner {
    enum RunError: Error {
        case unsupportedPlatform
        case noCore
        case coreFailedToStart(String)
        case buildFailed(String)

        var message: String {
            switch self {
            case .unsupportedPlatform: "Checking through a proxy is available only on Mac"
            case .noCore: "The Xray core isn't installed — download it in settings"
            case .coreFailedToStart(let s): "The core failed to start: \(s)"
            case .buildFailed(let s): "Couldn't build the config: \(s)"
            }
        }
    }

    /// Bring up the core for `node`, probe gstatic through it, tear it down.
    static func probe(node: ProxyNode, coreBinary: URL) async throws -> Socks5Probe.Result {
        #if os(macOS)
        let port = freePort()
        let config: String
        do { config = try XrayTestConfig.build(for: node, socksPort: port) }
        catch { throw RunError.buildFailed((error as? XrayTestConfig.BuildError).map(String.init(describing:)) ?? "\(error)") }

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("checknet-xray-\(port)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let configURL = dir.appendingPathComponent("config.json")
        try config.data(using: .utf8)?.write(to: configURL)

        let process = Process()
        process.executableURL = coreBinary
        process.arguments = ["run", "-c", configURL.path]
        let errPipe = Pipe()
        process.standardOutput = Pipe()
        process.standardError = errPipe
        do { try process.run() } catch { throw RunError.coreFailedToStart("\(error)") }
        defer { process.terminate() }

        // Wait until the SOCKS port accepts connections (core is ready).
        guard await waitForPort(port, deadline: 5) else {
            let err = String(data: errPipe.fileHandleForReading.availableData, encoding: .utf8) ?? ""
            throw RunError.coreFailedToStart(err.isEmpty ? "port \(port) didn't open" : err)
        }

        return try await Socks5Probe.probe(socksPort: port)
        #else
        throw RunError.unsupportedPlatform
        #endif
    }

    /// Brings the core up in-process for `node` and returns the live local SOCKS
    /// port, leaving it running. The caller owns teardown — call `XrayCore.stop()`
    /// when finished (e.g. after streaming egress checks through the port).
    static func startInProcess(node: ProxyNode) async throws -> Int {
        guard XrayCore.isAvailable else { throw RunError.noCore }
        let port = freePort()
        let config: String
        do { config = try XrayTestConfig.build(for: node, socksPort: port) }
        catch { throw RunError.buildFailed((error as? XrayTestConfig.BuildError).map(String.init(describing:)) ?? "\(error)") }

        XrayCore.stop()                                     // clear any previous global instance
        do { try XrayCore.run(configJSON: config) }
        catch { throw RunError.coreFailedToStart((error as? XrayCore.CoreError)?.message ?? "\(error)") }

        guard await waitForPort(port, deadline: 5) else {
            XrayCore.stop()
            throw RunError.coreFailedToStart("SOCKS port \(port) didn't open")
        }
        return port
    }

    // MARK: - helpers

    /// Ask the kernel for a free TCP port by binding to :0.
    private static func freePort() -> Int {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = 0
        _ = withUnsafePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &len) }
        }
        let port = Int(UInt16(bigEndian: addr.sin_port))
        return port > 0 ? port : Int.random(in: 20000...60000)
    }

    private static func waitForPort(_ port: Int, deadline seconds: Double) async -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if await tcpConnects(port: port) { return true }
            try? await Task.sleep(nanoseconds: 120_000_000)
        }
        return false
    }

    private static func tcpConnects(port: Int) async -> Bool {
        await withCheckedContinuation { cont in
            DispatchQueue.global().async {
                let fd = socket(AF_INET, SOCK_STREAM, 0)
                defer { close(fd) }
                var addr = sockaddr_in()
                addr.sin_family = sa_family_t(AF_INET)
                addr.sin_addr.s_addr = inet_addr("127.0.0.1")
                addr.sin_port = UInt16(port).bigEndian
                let ok = withUnsafePointer(to: &addr) { p in
                    p.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
                    }
                }
                cont.resume(returning: ok)
            }
        }
    }
}
