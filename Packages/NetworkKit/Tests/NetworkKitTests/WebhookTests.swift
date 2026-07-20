import XCTest
@testable import NetworkKit

final class WebhookTests: XCTestCase {
    // MARK: - Endpoint validation

    func testValidation() throws {
        XCTAssertNoThrow(try WebhookDispatcher.validate(urlString: "https://example.com/hook"))
        // Plain http off-device would leak results in the clear.
        XCTAssertThrowsError(try WebhookDispatcher.validate(urlString: "http://example.com/hook"))
        // Loopback is fine — it never leaves the device.
        XCTAssertNoThrow(try WebhookDispatcher.validate(urlString: "http://127.0.0.1:8080/hook"))
        XCTAssertNoThrow(try WebhookDispatcher.validate(urlString: "http://localhost:8080/hook"))
        XCTAssertThrowsError(try WebhookDispatcher.validate(urlString: "not a url"))
        XCTAssertThrowsError(try WebhookDispatcher.validate(urlString: "ftp://example.com"))
        XCTAssertThrowsError(try WebhookDispatcher.validate(urlString: ""))
    }

    // MARK: - Payload shape

    func testPayloadIsStableAndDocumented() throws {
        let event = WebhookEvent(
            event: "check.ping",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            host: "1.1.1.1", succeeded: true,
            verdict: "clean", headline: "Хост отвечает", detail: "5/5",
            latencyMillis: 12.5, lossPercent: 0,
            metadata: ["tool": "ping"]
        )
        let json = try JSONSerialization.jsonObject(with: WebhookDispatcher.encode(event)) as! [String: Any]

        // These key names are a public contract; renaming breaks integrations.
        XCTAssertEqual(json["version"] as? Int, 1)
        XCTAssertEqual(json["event"] as? String, "check.ping")
        XCTAssertEqual(json["host"] as? String, "1.1.1.1")
        XCTAssertEqual(json["succeeded"] as? Bool, true)
        XCTAssertEqual(json["verdict"] as? String, "clean")
        XCTAssertEqual(json["latencyMillis"] as? Double, 12.5)
        XCTAssertEqual(json["timestamp"] as? String, "2023-11-14T22:13:20Z", "timestamps must be ISO-8601 UTC")
    }

    func testSignatureIsStableHMAC() {
        let body = Data("payload".utf8)
        let sig = WebhookDispatcher.signature(body: body, secret: "topsecret")
        XCTAssertEqual(sig.count, 64, "sha256 hex is 64 chars")
        XCTAssertEqual(sig, WebhookDispatcher.signature(body: body, secret: "topsecret"), "must be deterministic")
        XCTAssertNotEqual(sig, WebhookDispatcher.signature(body: body, secret: "other"))
        XCTAssertNotEqual(sig, WebhookDispatcher.signature(body: Data("payload2".utf8), secret: "topsecret"))
    }

    // MARK: - Real delivery against a local receiver

    func testDeliversToLocalServerAndSignsPayload() async throws {
        let server = try LocalWebhookServer()
        defer { server.stop() }

        let dispatcher = WebhookDispatcher(
            url: URL(string: "http://127.0.0.1:\(server.port)/hook")!,
            secret: "shared-secret"
        )
        let event = WebhookEvent(event: "check.ping", host: "1.1.1.1", succeeded: true, latencyMillis: 9)
        let delivery = await dispatcher.send(event)

        XCTAssertTrue(delivery.succeeded, "delivery failed: \(delivery.error ?? "-")")
        XCTAssertEqual(delivery.attempts, 1)

        let received = try XCTUnwrap(server.lastRequest, "server saw no request")
        XCTAssertEqual(received.headers["x-checknet-event"], "check.ping")
        XCTAssertEqual(received.headers["content-type"], "application/json")

        // Verify the signature exactly as a receiving server would.
        let expected = "sha256=" + WebhookDispatcher.signature(body: received.body, secret: "shared-secret")
        XCTAssertEqual(received.headers["x-checknet-signature"], expected,
                       "receiver must be able to verify the body it actually got")

        let json = try JSONSerialization.jsonObject(with: received.body) as! [String: Any]
        XCTAssertEqual(json["host"] as? String, "1.1.1.1")
    }

    func testUnsignedWhenNoSecret() async throws {
        let server = try LocalWebhookServer()
        defer { server.stop() }

        let dispatcher = WebhookDispatcher(url: URL(string: "http://127.0.0.1:\(server.port)/hook")!)
        _ = await dispatcher.send(WebhookEvent(event: "check.ping", host: "h", succeeded: true))

        let received = try XCTUnwrap(server.lastRequest)
        XCTAssertNil(received.headers["x-checknet-signature"])
    }

    /// A 4xx means the receiver rejected the payload — retrying is pointless
    /// and would just multiply the noise.
    func testClientErrorIsNotRetried() async throws {
        let server = try LocalWebhookServer(status: 400)
        defer { server.stop() }

        let dispatcher = WebhookDispatcher(url: URL(string: "http://127.0.0.1:\(server.port)/hook")!, maxAttempts: 3)
        let delivery = await dispatcher.send(WebhookEvent(event: "e", host: "h", succeeded: false))

        XCTAssertFalse(delivery.succeeded)
        XCTAssertEqual(delivery.attempts, 1, "4xx must not be retried")
    }

    func testServerErrorIsRetried() async throws {
        let server = try LocalWebhookServer(status: 500)
        defer { server.stop() }

        let dispatcher = WebhookDispatcher(url: URL(string: "http://127.0.0.1:\(server.port)/hook")!, maxAttempts: 3)
        let delivery = await dispatcher.send(WebhookEvent(event: "e", host: "h", succeeded: false))

        XCTAssertFalse(delivery.succeeded)
        XCTAssertEqual(delivery.attempts, 3, "5xx should exhaust retries")
    }
}

// MARK: - Minimal HTTP receiver

/// A tiny blocking HTTP server used to prove deliveries actually arrive.
private final class LocalWebhookServer: @unchecked Sendable {
    struct Received {
        let headers: [String: String]
        let body: Data
    }

    let port: UInt16
    private let listener: FileHandle
    private let socketFD: Int32
    private let lock = NSLock()
    private var _lastRequest: Received?
    private var running = true

    var lastRequest: Received? {
        lock.lock(); defer { lock.unlock() }
        return _lastRequest
    }

    init(status: Int = 200) throws {
        // Everything here works on a local `fd`: touching the stored property
        // inside these closures would capture a half-initialised self.
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0 // let the kernel pick
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bound = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, listen(fd, 4) == 0 else {
            close(fd)
            throw NSError(domain: "LocalWebhookServer", code: 1)
        }

        var actual = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &actual) { pointer in
            _ = pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &len) }
        }
        port = actual.sin_port.bigEndian
        socketFD = fd
        listener = FileHandle(fileDescriptor: fd)

        Thread.detachNewThread { [weak self] in self?.acceptLoop(status: status) }
    }

    private func acceptLoop(status: Int) {
        while running {
            let client = accept(socketFD, nil, nil)
            guard client >= 0 else { return }
            var raw = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            // Read headers, then exactly Content-Length bytes of body.
            while true {
                let n = recv(client, &buffer, buffer.count, 0)
                if n <= 0 { break }
                raw.append(contentsOf: buffer[0..<n])
                guard let headerEnd = raw.range(of: Data("\r\n\r\n".utf8)) else { continue }
                let head = String(decoding: raw[..<headerEnd.lowerBound], as: UTF8.self)
                let length = head.split(separator: "\r\n")
                    .first { $0.lowercased().hasPrefix("content-length:") }
                    .flatMap { Int($0.split(separator: ":")[1].trimmingCharacters(in: .whitespaces)) } ?? 0
                if raw.distance(from: headerEnd.upperBound, to: raw.endIndex) >= length { break }
            }

            if let headerEnd = raw.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: raw[..<headerEnd.lowerBound], as: UTF8.self)
                var headers: [String: String] = [:]
                for line in head.split(separator: "\r\n").dropFirst() {
                    let parts = line.split(separator: ":", maxSplits: 1)
                    if parts.count == 2 {
                        headers[parts[0].lowercased()] = parts[1].trimmingCharacters(in: .whitespaces)
                    }
                }
                let body = Data(raw[headerEnd.upperBound...])
                lock.lock(); _lastRequest = Received(headers: headers, body: body); lock.unlock()
            }

            let response = "HTTP/1.1 \(status) OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            _ = response.withCString { send(client, $0, strlen($0), 0) }
            close(client)
        }
    }

    func stop() {
        running = false
        close(socketFD)
    }
}
