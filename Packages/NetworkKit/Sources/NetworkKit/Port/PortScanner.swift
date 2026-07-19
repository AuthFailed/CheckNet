import Foundation

public struct PortCheckResult: Sendable, Hashable, Codable, Identifiable {
    public var id: Int { port }
    public let port: Int
    public let isOpen: Bool
    public let latencyMillis: Double?
    public let serviceName: String?
    public let error: String?

    public init(port: Int, isOpen: Bool, latencyMillis: Double?, serviceName: String?, error: String? = nil) {
        self.port = port
        self.isOpen = isOpen
        self.latencyMillis = latencyMillis
        self.serviceName = serviceName
        self.error = error
    }
}

/// TCP-connect based port checking / scanning.
public struct PortScanner: Sendable {
    public init() {}

    /// Checks a single TCP port via a full connect.
    public func check(host: String, port: Int, timeout: TimeInterval = 2.0, family: IPFamily? = nil) async -> PortCheckResult {
        do {
            let endpoint = try await HostResolver.resolveFirst(host: host, port: UInt16(port), family: family)
            let result: (fd: Int32, latencyMillis: Double) = try await withCheckedThrowingContinuation { cont in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let r = try TCPTransport.connect(endpoint: endpoint, timeout: timeout)
                        cont.resume(returning: r)
                    } catch { cont.resume(throwing: error) }
                }
            }
            close(result.fd)
            return PortCheckResult(port: port, isOpen: true, latencyMillis: result.latencyMillis, serviceName: Self.service(for: port))
        } catch {
            let isTimeout = (error as? NetworkError) == .timedOut
            return PortCheckResult(port: port, isOpen: false, latencyMillis: nil,
                                   serviceName: Self.service(for: port),
                                   error: isTimeout ? nil : error.localizedDescription)
        }
    }

    /// Scans many ports with bounded concurrency, streaming results as they complete.
    public func scan(host: String, ports: [Int], timeout: TimeInterval = 1.5, concurrency: Int = 32) -> AsyncStream<PortCheckResult> {
        AsyncStream { continuation in
            let task = Task {
                await withTaskGroup(of: PortCheckResult.self) { group in
                    var iterator = ports.makeIterator()
                    var active = 0
                    func addNext() {
                        guard let p = iterator.next() else { return }
                        active += 1
                        group.addTask { await check(host: host, port: p, timeout: timeout) }
                    }
                    for _ in 0..<Swift.max(1, concurrency) { addNext() }
                    while active > 0 {
                        guard let result = await group.next() else { break }
                        active -= 1
                        if Task.isCancelled { break }
                        continuation.yield(result)
                        addNext()
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Common service names for well-known ports.
    public static func service(for port: Int) -> String? { Self.wellKnown[port] }

    /// A curated list of common ports for a quick scan.
    public static let commonPorts: [Int] = [
        20, 21, 22, 23, 25, 53, 67, 80, 110, 123, 143, 161, 389, 443, 445,
        465, 587, 993, 995, 1080, 1433, 1521, 3306, 3389, 5432, 5900, 6379,
        8080, 8443, 8888, 9000, 27017
    ]

    static let wellKnown: [Int: String] = [
        20: "FTP-Data", 21: "FTP", 22: "SSH", 23: "Telnet", 25: "SMTP", 53: "DNS",
        67: "DHCP", 80: "HTTP", 110: "POP3", 123: "NTP", 143: "IMAP", 161: "SNMP",
        389: "LDAP", 443: "HTTPS", 445: "SMB", 465: "SMTPS", 587: "Submission",
        993: "IMAPS", 995: "POP3S", 1080: "SOCKS", 1433: "MSSQL", 1521: "Oracle",
        3306: "MySQL", 3389: "RDP", 5432: "PostgreSQL", 5900: "VNC", 6379: "Redis",
        8080: "HTTP-Alt", 8443: "HTTPS-Alt", 8888: "HTTP-Alt", 9000: "SonarQube", 27017: "MongoDB"
    ]
}
