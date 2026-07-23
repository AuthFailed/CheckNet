import Foundation

/// Runs availability checks from measurement nodes around the world ("World
/// Ping" and friends). Supports every check type the backend offers (ping,
/// HTTP, TCP, DNS, UDP) and lets the caller either pick nodes at random or
/// target specific ones (e.g. only Russian or European nodes).
///
/// The flow is two-step: initiate a check (returns a request id and the node
/// list), then poll for results until every node has reported or a deadline
/// passes. Results are streamed so the list fills in as nodes answer.
public struct WorldProbe: Sendable {
    public init() {}

    /// The measurement backend's origin. Kept in one place; referenced nowhere else.
    private static let base = "https://check-host.net"

    public enum CheckType: String, Sendable, CaseIterable, Codable {
        case ping, http, tcp, dns, udp
        public var path: String { "check-\(rawValue)" }
    }

    // MARK: Node list

    /// Every node the backend currently offers, for building a country picker.
    public func availableNodes() async throws -> [WorldProbeNode] {
        guard let url = URL(string: "\(Self.base)/nodes/hosts") else {
            throw NetworkError.protocolError("bad url")
        }
        let data = try await Self.fetch(url)
        guard let nodes = Self.parseNodeList(data) else {
            throw NetworkError.protocolError("не удалось получить список узлов")
        }
        return nodes.sorted { ($0.country, $0.city) < ($1.country, $1.city) }
    }

    // MARK: Run a check

    /// Streams results for a check. Pass explicit `nodeNames` to target nodes, or
    /// leave empty to pick up to `maxNodes` at random.
    public func run(type: CheckType, host: String,
                    nodeNames: [String] = [], maxNodes: Int = 30) -> AsyncStream<WorldProbeEvent> {
        AsyncStream(bufferingPolicy: .unbounded) { continuation in
            let task = Task {
                await execute(type: type, host: host, nodeNames: nodeNames,
                              maxNodes: maxNodes, continuation: continuation)
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func execute(type: CheckType, host: String, nodeNames: [String], maxNodes: Int,
                         continuation: AsyncStream<WorldProbeEvent>.Continuation) async {
        let target = host.trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty, var components = URLComponents(string: "\(Self.base)/\(type.path)") else {
            continuation.yield(.failed("Некорректный адрес")); continuation.finish(); return
        }
        var items = [URLQueryItem(name: "host", value: target)]
        if nodeNames.isEmpty {
            items.append(URLQueryItem(name: "max_nodes", value: String(maxNodes)))
        } else {
            items.append(contentsOf: nodeNames.map { URLQueryItem(name: "node", value: $0) })
        }
        components.queryItems = items
        guard let url = components.url, let data = try? await Self.fetch(url),
              let (requestId, nodes) = Self.parseInitiate(data) else {
            continuation.yield(.failed("Сервис проверки не принял запрос. Попробуйте позже."))
            continuation.finish(); return
        }
        guard !nodes.isEmpty else {
            continuation.yield(.failed("Нет доступных узлов для проверки")); continuation.finish(); return
        }

        var byName = Dictionary(uniqueKeysWithValues: nodes.map { ($0.name, WorldProbeResult(node: $0)) })
        continuation.yield(.started(Self.sorted(byName)))

        // Poll until every node has an outcome or ~25s elapse.
        let deadline = MonoClock.nanos() &+ 25 * 1_000_000_000
        while MonoClock.nanos() < deadline, !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1.5))
            guard let resultURL = URL(string: "\(Self.base)/check-result/\(requestId)"),
                  let resultData = try? await Self.fetch(resultURL) else { continue }
            let outcomes = Self.parseResults(type: type, data: resultData)
            var pending = 0
            for (name, var result) in byName {
                if result.status == .pending, let outcome = outcomes[name] {
                    result.apply(outcome)
                    byName[name] = result
                    continuation.yield(.update(result))
                } else if result.status == .pending {
                    pending += 1
                }
            }
            if pending == 0 { break }
        }

        // Anything still pending timed out on our side.
        for (name, var result) in byName where result.status == .pending {
            result.status = .error
            result.summary = "нет ответа"
            byName[name] = result
        }
        continuation.yield(.finished(Self.sorted(byName)))
        continuation.finish()
    }

    private static func sorted(_ byName: [String: WorldProbeResult]) -> [WorldProbeResult] {
        byName.values.sorted { ($0.node.country, $0.node.city, $0.node.name) < ($1.node.country, $1.node.city, $1.node.name) }
    }

    // MARK: Networking

    private static func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let (data, _) = try await URLSession.shared.data(for: request)
        return data
    }

    // MARK: Parsing

    static func parseNodeList(_ data: Data) -> [WorldProbeNode]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let nodes = root["nodes"] as? [String: Any] else { return nil }
        return nodes.compactMap { name, value in
            guard let info = value as? [String: Any],
                  let location = info["location"] as? [Any] else { return nil }
            return WorldProbeNode(
                name: name,
                countryCode: (location.first as? String) ?? "",
                country: (location.count > 1 ? location[1] as? String : nil) ?? "",
                city: (location.count > 2 ? location[2] as? String : nil) ?? "",
                ip: info["ip"] as? String,
                asn: info["asn"] as? String
            )
        }
    }

    static func parseInitiate(_ data: Data) -> (requestId: String, nodes: [WorldProbeNode])? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (root["ok"] as? NSNumber)?.intValue == 1,
              let requestId = root["request_id"] as? String,
              let nodes = root["nodes"] as? [String: Any] else { return nil }
        let parsed: [WorldProbeNode] = nodes.compactMap { name, value in
            guard let location = value as? [Any] else { return nil }
            return WorldProbeNode(
                name: name,
                countryCode: (location.first as? String) ?? "",
                country: (location.count > 1 ? location[1] as? String : nil) ?? "",
                city: (location.count > 2 ? location[2] as? String : nil) ?? "",
                ip: location.count > 3 ? location[3] as? String : nil,
                asn: location.count > 4 ? location[4] as? String : nil
            )
        }
        return (requestId, parsed)
    }

    /// One node's normalised outcome for a given check type.
    struct Outcome { var status: WorldProbeResult.Status; var rtt: Double?; var loss: Double?; var summary: String }

    static func parseResults(type: CheckType, data: Data) -> [String: Outcome] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        var out: [String: Outcome] = [:]
        for (name, value) in root {
            if value is NSNull { continue }                 // still checking
            guard let array = value as? [Any] else { continue }
            if let outcome = outcome(type: type, nodeValue: array) { out[name] = outcome }
        }
        return out
    }

    private static func outcome(type: CheckType, nodeValue: [Any]) -> Outcome? {
        switch type {
        case .ping:
            // [[ ["OK",t,ip], ["TIMEOUT",t], ... ]] ; [[null]] = resolve failure
            guard let attempts = nodeValue.first as? [Any] else { return nil }
            var rtts: [Double] = []
            var total = 0
            for attempt in attempts {
                guard let a = attempt as? [Any], let status = a.first as? String else { continue }
                total += 1
                if status == "OK", a.count > 1, let t = (a[1] as? NSNumber)?.doubleValue { rtts.append(t * 1000) }
            }
            guard total > 0 else { return Outcome(status: .error, rtt: nil, loss: nil, summary: "имя не разрешилось") }
            let avg = rtts.isEmpty ? nil : rtts.reduce(0, +) / Double(rtts.count)
            let loss = Double(total - rtts.count) / Double(total) * 100
            if rtts.isEmpty {
                return Outcome(status: .failed, rtt: nil, loss: 100, summary: "недоступен")
            }
            let lossText = loss > 0 ? ", потери \(Int(loss))%" : ""
            return Outcome(status: .ok, rtt: avg, loss: loss, summary: "\(Int(avg!)) мс\(lossText)")
        case .http:
            // [[ success, time, message, code, ip ]]
            guard let r = nodeValue.first as? [Any], let success = (r.first as? NSNumber)?.intValue else { return nil }
            let time = (r.count > 1 ? (r[1] as? NSNumber)?.doubleValue : nil).map { $0 * 1000 }
            let message = r.count > 2 ? r[2] as? String : nil
            let code = r.count > 3 ? r[3] as? String : nil
            let head = [code, message].compactMap { $0 }.joined(separator: " ")
            if success == 1 {
                return Outcome(status: .ok, rtt: time, loss: nil,
                               summary: [time.map { "\(Int($0)) мс" }, head.isEmpty ? nil : head].compactMap { $0 }.joined(separator: " · "))
            }
            return Outcome(status: .failed, rtt: time, loss: nil, summary: head.isEmpty ? "ошибка" : head)
        case .tcp, .udp:
            // [{"time":0.03,"address":"..."}] or [{"error":"..."}]
            guard let dict = nodeValue.first as? [String: Any] else { return nil }
            if let error = dict["error"] as? String {
                return Outcome(status: .failed, rtt: nil, loss: nil, summary: error)
            }
            let time = ((dict["time"] as? NSNumber)?.doubleValue).map { $0 * 1000 }
            let address = dict["address"] as? String
            let summary = [time.map { "подключение \(Int($0)) мс" }, address].compactMap { $0 }.joined(separator: " · ")
            return Outcome(status: .ok, rtt: time, loss: nil, summary: summary.isEmpty ? "подключено" : summary)
        case .dns:
            // [{"A":[...],"AAAA":[...],"TTL":n}]
            guard let dict = nodeValue.first as? [String: Any] else { return nil }
            let a = (dict["A"] as? [String]) ?? []
            let aaaa = (dict["AAAA"] as? [String]) ?? []
            let all = a + aaaa
            guard !all.isEmpty else { return Outcome(status: .failed, rtt: nil, loss: nil, summary: "имя не разрешилось") }
            let extra = all.count > 1 ? " (+\(all.count - 1))" : ""
            return Outcome(status: .ok, rtt: nil, loss: nil, summary: "\(all.first!)\(extra)")
        }
    }
}

// MARK: - Models

public struct WorldProbeNode: Sendable, Hashable, Codable, Identifiable {
    public var id: String { name }
    public let name: String
    public let countryCode: String
    public let country: String
    public let city: String
    public let ip: String?
    public let asn: String?

    public var flagEmoji: String? { IPGeo.flag(countryCode) }
}

public struct WorldProbeResult: Sendable, Hashable, Codable, Identifiable {
    public var id: String { node.name }
    public let node: WorldProbeNode
    public var status: Status
    public var summary: String
    public var rttMillis: Double?
    public var lossPercent: Double?

    public enum Status: String, Sendable, Codable { case pending, ok, failed, error }

    public init(node: WorldProbeNode) {
        self.node = node
        self.status = .pending
        self.summary = "проверяется…"
        self.rttMillis = nil
        self.lossPercent = nil
    }

    mutating func apply(_ outcome: WorldProbe.Outcome) {
        status = outcome.status
        rttMillis = outcome.rtt
        lossPercent = outcome.loss
        summary = outcome.summary
    }
}

public enum WorldProbeEvent: Sendable {
    case started([WorldProbeResult])
    case update(WorldProbeResult)
    case finished([WorldProbeResult])
    case failed(String)
}
