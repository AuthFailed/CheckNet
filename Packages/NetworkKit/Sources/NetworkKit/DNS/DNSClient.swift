import Foundation

/// A UDP DNS client that queries a specific resolver, enabling resolver
/// comparison, latency measurement, DNSSEC (AD bit) and tamper detection.
public struct DNSClient: Sendable {
    public init() {}

    public struct Options: Sendable {
        public var timeout: TimeInterval
        public var dnssec: Bool
        public var port: UInt16
        public init(timeout: TimeInterval = 3.0, dnssec: Bool = false, port: UInt16 = 53) {
            self.timeout = timeout
            self.dnssec = dnssec
            self.port = port
        }
        public static let `default` = Options()
    }

    /// Performs one query against `resolver` (an IP address).
    public func query(
        name: String,
        type: DNSRecordType,
        resolver: String,
        options: Options = .default
    ) async throws -> DNSResult {
        let endpoint = try await HostResolver.resolveFirst(host: resolver, port: options.port)
        let id = UInt16.random(in: 1...UInt16.max)
        let queryBytes = DNSMessage.encodeQuery(id: id, name: name, type: type, dnssec: options.dnssec)

        let start = MonoClock.nanos()
        let response = try await UDPExchange.request(
            endpoint: endpoint,
            payload: queryBytes,
            timeout: options.timeout
        )
        var latency = MonoClock.millisSince(start)

        var decoded = try DNSMessage.decode(response)
        // Retry over TCP when the UDP answer is truncated (large TXT/DNSSEC sets).
        if decoded.header.truncated {
            let tcpStart = MonoClock.nanos()
            let tcpResponse = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[UInt8], Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let r = try TCPTransport.dnsRequest(endpoint: endpoint, query: queryBytes, timeout: options.timeout)
                        cont.resume(returning: r)
                    } catch { cont.resume(throwing: error) }
                }
            }
            decoded = try DNSMessage.decode(tcpResponse)
            latency = MonoClock.millisSince(tcpStart)
        }
        return DNSResult(
            resolver: resolver,
            queryName: name,
            queryType: type,
            responseCode: DNSResponseCode(rawCode: decoded.header.rcode),
            answers: decoded.answers,
            authorities: decoded.authorities,
            additionals: decoded.additionals,
            latencyMillis: latency,
            authenticated: decoded.header.authenticated,
            truncated: decoded.header.truncated
        )
    }

    /// Queries several resolvers in parallel for the same name/type.
    public func compareResolvers(
        name: String,
        type: DNSRecordType,
        resolvers: [DNSResolverInfo],
        options: Options = .default
    ) async -> [DNSResolverComparisonRow] {
        await withTaskGroup(of: DNSResolverComparisonRow.self) { group in
            for r in resolvers {
                group.addTask {
                    do {
                        let res = try await query(name: name, type: type, resolver: r.address, options: options)
                        return DNSResolverComparisonRow(resolver: r, result: res, error: nil)
                    } catch {
                        return DNSResolverComparisonRow(resolver: r, result: nil, error: error.localizedDescription)
                    }
                }
            }
            var rows: [DNSResolverComparisonRow] = []
            for await row in group { rows.append(row) }
            // Preserve the input order.
            return resolvers.compactMap { r in rows.first { $0.resolver.id == r.id } }
        }
    }

    /// Compares resolver answers and flags likely tampering / split-horizon.
    public func detectTampering(
        name: String,
        resolvers: [DNSResolverInfo] = DNSResolverInfo.presets,
        options: Options = .default
    ) async -> DNSTamperReport {
        let rows = await compareResolvers(name: name, type: .a, resolvers: resolvers, options: options)
        let answered = rows.filter { $0.result?.responseCode == .noError && !($0.result?.answers.isEmpty ?? true) }
        let answerSets = answered.compactMap { $0.result?.normalizedAnswerSet }.filter { !$0.isEmpty }

        var findings: [String] = []
        var suspicious = false

        // Divergent answers across resolvers.
        let uniqueSets = Set(answerSets.map { $0.sorted().joined(separator: ",") })
        if uniqueSets.count > 1 {
            suspicious = true
            findings.append("Резолверы вернули разные адреса — возможна подмена или split-horizon.")
        }

        // NXDOMAIN / REFUSED from some but not all resolvers.
        let blocked = rows.filter { r in
            if let rc = r.result?.responseCode { return rc == .nxDomain || rc == .refused }
            return false
        }
        if !blocked.isEmpty && blocked.count < rows.count {
            suspicious = true
            findings.append("Часть резолверов заблокировала запрос (\(blocked.map { $0.resolver.name }.joined(separator: ", "))).")
        }

        // Private/loopback answers for a public host suggest injection.
        for row in answered {
            for ip in row.result?.normalizedAnswerSet ?? [] where Self.isPrivateOrLoopback(ip) {
                suspicious = true
                findings.append("\(row.resolver.name) вернул приватный адрес \(ip) для публичного хоста.")
            }
        }

        if findings.isEmpty { findings.append("Ответы согласованы между резолверами.") }
        return DNSTamperReport(name: name, rows: rows, suspicious: suspicious, findings: findings)
    }

    static func isPrivateOrLoopback(_ ip: String) -> Bool {
        if ip.hasPrefix("127.") || ip == "0.0.0.0" || ip.hasPrefix("10.") || ip.hasPrefix("192.168.") { return true }
        if ip.hasPrefix("169.254.") { return true }
        if ip.hasPrefix("172.") {
            let parts = ip.split(separator: ".")
            if parts.count > 1, let second = Int(parts[1]), (16...31).contains(second) { return true }
        }
        return false
    }
}

public struct DNSResolverComparisonRow: Sendable, Identifiable {
    public var id: String { resolver.id }
    public let resolver: DNSResolverInfo
    public let result: DNSResult?
    public let error: String?
}

public struct DNSTamperReport: Sendable {
    public let name: String
    public let rows: [DNSResolverComparisonRow]
    public let suspicious: Bool
    public let findings: [String]
}
