import XCTest
@testable import NetworkKit

final class SpeedTests: XCTestCase {
    func testFetchServerList() async throws {
        try requiresInternet()
        let servers: [IperfServer]
        do {
            servers = try await IperfServerList().fetch()
        } catch {
            throw XCTSkip("server list unreachable: \(error.localizedDescription)")
        }
        print("iperf3 servers: \(servers.count)")
        XCTAssertGreaterThan(servers.count, 5)
        let withReverse = servers.filter { $0.supportsReverse }
        print("  with reverse: \(withReverse.count); sample: \(servers.prefix(3).map { "\($0.host):\($0.portRange) \($0.locationLabel)" })")
        XCTAssertTrue(servers.allSatisfy { $0.port > 0 })
    }

    func testPortRangeParsing() {
        let s = IperfServer(host: "h", portRange: "5201-5205", options: "-R", gbps: "10",
                            continent: "EU", country: "DE", site: "Berlin", provider: "X")
        XCTAssertEqual(s.port, 5201)
        XCTAssertEqual(s.ports, [5201, 5202, 5203, 5204, 5205])
        XCTAssertTrue(s.supportsReverse)
    }

    func testIperfDownloadAgainstPublicServer() async throws {
        try requiresInternet()
        let servers: [IperfServer]
        do { servers = try await IperfServerList().fetch() }
        catch { throw XCTSkip("server list unreachable") }

        // Try a few reverse-capable servers until one completes.
        let candidates = Array(servers.filter { $0.supportsReverse }.prefix(6))
        guard !candidates.isEmpty else { throw XCTSkip("no reverse-capable servers") }

        for server in candidates {
            var download: Double?
            var failed: String?
            let config = IperfClient.Config(duration: 4, streams: 4, download: true, upload: false)
            for await event in IperfClient().run(server: server, config: config) {
                switch event {
                case .sample(let s): print("  \(server.host): \(String(format: "%.1f", s.mbps)) Mbps @ \(String(format: "%.1f", s.seconds))s")
                case .finished(let r): download = r.downloadMbps
                case .failed(let reason): failed = reason
                default: break
                }
            }
            if let download, download > 0 {
                print("iperf3 download from \(server.host) (\(server.locationLabel)): \(String(format: "%.1f", download)) Mbps")
                XCTAssertGreaterThan(download, 0)
                return
            } else {
                print("  \(server.host) failed: \(failed ?? "no throughput")")
            }
        }
        throw XCTSkip("no public iperf3 server completed a test from this environment")
    }
}
