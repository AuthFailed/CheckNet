import XCTest

/// Marks a test as depending on real internet egress.
///
/// Most of the suite probes live hosts on purpose — that is how we know a check
/// works. But a hosted runner is not a dependable network: ICMP is often
/// filtered, DNS and TLS to third-party hosts flake, and an unrelated outage
/// would then redden every pull request. So CI runs the deterministic tests as
/// a blocking gate with `CHECKNET_SKIP_NETWORK_TESTS=1`, and runs the full
/// suite separately without it, where a failure is a signal rather than a veto.
///
/// Locally the variable is unset, so `swift test` runs everything — a check is
/// still only considered done when it has been proven against a real host.
///
/// Call it as the first line of any test that touches the network:
/// ```swift
/// func testPingCloudflare() async throws {
///     try requiresInternet()
///     …
/// }
/// ```
extension XCTestCase {
    func requiresInternet(file: StaticString = #filePath, line: UInt = #line) throws {
        guard ProcessInfo.processInfo.environment["CHECKNET_SKIP_NETWORK_TESTS"] == "1" else { return }
        throw XCTSkip("needs real network egress; CHECKNET_SKIP_NETWORK_TESTS=1", file: file, line: line)
    }
}
