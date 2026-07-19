import Foundation

public struct SpeedSample: Sendable, Hashable {
    public let seconds: Double
    public let mbps: Double
    public let direction: SpeedDirection
}

public enum SpeedDirection: String, Sendable { case download, upload }

public struct SpeedResult: Sendable, Hashable {
    public var downloadMbps: Double?
    public var uploadMbps: Double?
    public var server: String
    public var latencyMillis: Double?
}

public enum SpeedEvent: Sendable {
    case phase(String)
    case sample(SpeedSample)
    case finished(SpeedResult)
    case failed(String)
}

/// A pure-Swift iperf3 client (control channel + TCP data streams) implementing
/// the iperf3 wire protocol, so it runs on iOS/macOS without libiperf. Supports
/// download (reverse) and upload against public iperf3 servers.
public final class IperfClient: Sendable {
    public init() {}

    // iperf3 control-channel state bytes (iperf_api.h).
    private enum State: Int8 {
        case testStart = 1, testRunning = 2, testEnd = 4
        case paramExchange = 9, createStreams = 10
        case exchangeResults = 13, displayResults = 14
        case iperfDone = 16, accessDenied = -1, serverError = -2
    }

    public struct Config: Sendable {
        public var duration: TimeInterval
        public var streams: Int
        public var download: Bool
        public var upload: Bool
        public init(duration: TimeInterval = 10, streams: Int = 6, download: Bool = true, upload: Bool = true) {
            self.duration = duration
            self.streams = max(1, min(streams, 32))
            self.download = download
            self.upload = upload
        }
    }

    public func run(server: IperfServer, config: Config = Config()) -> AsyncStream<SpeedEvent> {
        AsyncStream(bufferingPolicy: .unbounded) { continuation in
            let box = CancelBox()
            continuation.onTermination = { _ in box.cancel() }
            DispatchQueue.global(qos: .userInitiated).async {
                var result = SpeedResult(downloadMbps: nil, uploadMbps: nil, server: server.host, latencyMillis: nil)
                do {
                    if config.download {
                        continuation.yield(.phase("Загрузка (download)…"))
                        result.downloadMbps = try self.session(server: server, config: config, reverse: true,
                                                               continuation: continuation, direction: .download, cancel: box)
                    }
                    if config.upload && !box.isCancelled {
                        continuation.yield(.phase("Отдача (upload)…"))
                        result.uploadMbps = try self.session(server: server, config: config, reverse: false,
                                                             continuation: continuation, direction: .upload, cancel: box)
                    }
                    continuation.yield(.finished(result))
                } catch {
                    let reason = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    continuation.yield(.failed(reason))
                }
                continuation.finish()
            }
        }
    }

    /// Runs one iperf3 test session in a single direction; returns average Mbps.
    private func session(server: IperfServer, config: Config, reverse: Bool,
                         continuation: AsyncStream<SpeedEvent>.Continuation,
                         direction: SpeedDirection, cancel: CancelBox) throws -> Double {
        let cookie = Self.makeCookie()
        let controlEndpoint = try resolveSync(host: server.host, port: UInt16(server.port))

        let (control, _) = try TCPTransport.connect(endpoint: controlEndpoint, timeout: 8)
        defer { close(control) }
        try TCPTransport.writeAll(fd: control, bytes: Array(cookie.utf8))

        var dataFds: [Int32] = []
        defer { dataFds.forEach { close($0) } }

        let blockSize = 131_072
        let sendBlock = [UInt8](repeating: 0, count: blockSize)
        var totalBytes = 0
        var startNanos: UInt64 = 0
        var lastSample: UInt64 = 0

        while !cancel.isCancelled {
            let stateByte = try TCPTransport.readExactly(fd: control, count: 1, timeout: 15)
            guard let state = State(rawValue: Int8(bitPattern: stateByte[0])) else { continue }

            switch state {
            case .paramExchange:
                let params = Self.paramsJSON(cookie: cookie, duration: config.duration,
                                             streams: config.streams, reverse: reverse, blockSize: blockSize)
                try writeJSON(fd: control, data: params)

            case .createStreams:
                for _ in 0..<config.streams {
                    let (fd, _) = try TCPTransport.connect(endpoint: controlEndpoint, timeout: 8)
                    setNonBlocking(fd)
                    try TCPTransport.writeAll(fd: fd, bytes: Array(cookie.utf8))
                    dataFds.append(fd)
                }

            case .testStart:
                startNanos = MonoClock.nanos()
                lastSample = startNanos

            case .testRunning:
                startNanos = MonoClock.nanos()
                lastSample = startNanos
                let deadline = startNanos + UInt64(config.duration * 1_000_000_000)
                var buffer = [UInt8](repeating: 0, count: blockSize)

                while MonoClock.nanos() < deadline && !cancel.isCancelled {
                    var pollfds = dataFds.map { pollfd(fd: $0, events: Int16(reverse ? POLLIN : POLLOUT), revents: 0) }
                    let pr = poll(&pollfds, nfds_t(pollfds.count), 200)
                    if pr > 0 {
                        for (i, pfd) in pollfds.enumerated() {
                            let fd = dataFds[i]
                            if reverse, (pfd.revents & Int16(POLLIN)) != 0 {
                                let n = buffer.withUnsafeMutableBytes { recv(fd, $0.baseAddress, blockSize, 0) }
                                if n > 0 { totalBytes += n }
                            } else if !reverse, (pfd.revents & Int16(POLLOUT)) != 0 {
                                let n = sendBlock.withUnsafeBytes { send(fd, $0.baseAddress, blockSize, 0) }
                                if n > 0 { totalBytes += n }
                            }
                        }
                    }
                    // Emit ~2 samples/sec.
                    let now = MonoClock.nanos()
                    if now - lastSample > 500_000_000 {
                        let elapsed = Double(now - startNanos) / 1_000_000_000
                        let mbps = elapsed > 0 ? Double(totalBytes) * 8 / elapsed / 1_000_000 : 0
                        continuation.yield(.sample(SpeedSample(seconds: elapsed, mbps: mbps, direction: direction)))
                        lastSample = now
                    }
                }
                // Signal end of test to the server.
                try? TCPTransport.writeAll(fd: control, bytes: [UInt8(bitPattern: State.testEnd.rawValue)])

            case .exchangeResults:
                // Send our (minimal) results, then read the server's.
                let results = Self.resultsJSON(bytes: totalBytes, duration: config.duration, streams: config.streams)
                try writeJSON(fd: control, data: results)
                _ = try? readJSON(fd: control)

            case .displayResults:
                try? TCPTransport.writeAll(fd: control, bytes: [UInt8(bitPattern: State.iperfDone.rawValue)])
                let elapsed = max(Double(MonoClock.nanos() - startNanos) / 1_000_000_000, 0.001)
                return Double(totalBytes) * 8 / elapsed / 1_000_000

            case .iperfDone:
                let elapsed = max(Double(MonoClock.nanos() - startNanos) / 1_000_000_000, 0.001)
                return Double(totalBytes) * 8 / elapsed / 1_000_000

            case .accessDenied:
                throw NetworkError.protocolError("Сервер занят (access denied)")
            case .serverError:
                throw NetworkError.protocolError("Ошибка сервера iperf3")
            case .testEnd:
                continue
            }
        }
        throw NetworkError.cancelled
    }

    // MARK: JSON control messages

    private func writeJSON(fd: Int32, data: Data) throws {
        var framed = [UInt8]()
        let len = UInt32(data.count)
        framed.append(UInt8((len >> 24) & 0xFF)); framed.append(UInt8((len >> 16) & 0xFF))
        framed.append(UInt8((len >> 8) & 0xFF)); framed.append(UInt8(len & 0xFF))
        framed.append(contentsOf: data)
        try TCPTransport.writeAll(fd: fd, bytes: framed)
    }

    private func readJSON(fd: Int32) throws -> Data {
        let lenBytes = try TCPTransport.readExactly(fd: fd, count: 4, timeout: 15)
        let len = (Int(lenBytes[0]) << 24) | (Int(lenBytes[1]) << 16) | (Int(lenBytes[2]) << 8) | Int(lenBytes[3])
        guard len > 0, len < 1 << 20 else { return Data() }
        let payload = try TCPTransport.readExactly(fd: fd, count: len, timeout: 15)
        return Data(payload)
    }

    private static func paramsJSON(cookie: String, duration: TimeInterval, streams: Int, reverse: Bool, blockSize: Int) -> Data {
        let params: [String: Any] = [
            "tcp": true, "omit": 0, "time": Int(duration), "num_streams": streams,
            "blockcount": 0, "MSS": 0, "nodelay": false, "parallel": streams,
            "reverse": reverse, "bidirectional": false, "window": 0, "len": blockSize,
            "bandwidth": 0, "pacing_timer": 1000, "client_version": "3.16", "cookie": cookie
        ]
        return (try? JSONSerialization.data(withJSONObject: params)) ?? Data()
    }

    private static func resultsJSON(bytes: Int, duration: TimeInterval, streams: Int) -> Data {
        // A minimal but well-formed results object; the server mostly needs the streams array.
        let stream: [String: Any] = [
            "id": 1, "bytes": bytes, "retransmits": 0, "jitter": 0, "errors": 0, "packets": 0,
            "start_time": 0, "end_time": duration
        ]
        let obj: [String: Any] = ["cpu_util_total": 0, "cpu_util_user": 0, "cpu_util_system": 0,
                                  "sender_has_retransmits": 0, "streams": [stream]]
        return (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
    }

    private static func makeCookie() -> String {
        let chars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        var s = ""
        for _ in 0..<36 { s.append(chars.randomElement()!) }
        return s // 36 chars; iperf pads/uses up to COOKIE_SIZE-1
    }

    private func resolveSync(host: String, port: UInt16) throws -> ResolvedEndpoint {
        let sem = DispatchSemaphore(value: 0)
        let box = ResolveBox()
        Task {
            do { box.set(.success(try await HostResolver.resolveFirst(host: host, port: port))) }
            catch { box.set(.failure(error)) }
            sem.signal()
        }
        sem.wait()
        return try box.get()
    }

    private func setNonBlocking(_ fd: Int32) {
        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
    }
}

/// Thread-safe holder to bridge an async resolve into a synchronous context.
private final class ResolveBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Result<ResolvedEndpoint, Error>?
    func set(_ v: Result<ResolvedEndpoint, Error>) { lock.lock(); value = v; lock.unlock() }
    func get() throws -> ResolvedEndpoint {
        lock.lock(); defer { lock.unlock() }
        guard let value else { throw NetworkError.timedOut }
        return try value.get()
    }
}

/// Thread-safe cancellation flag.
final class CancelBox: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}
