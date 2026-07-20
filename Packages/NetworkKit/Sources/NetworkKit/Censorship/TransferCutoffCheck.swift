import Foundation

/// One probe run and what it observed.
public struct CutoffProbe: Sendable, Codable, Hashable {
    public enum Variant: String, Sendable, Codable {
        /// Accumulate payload in 4 KB steps until the connection dies.
        case byteAccumulation
        /// Same tiny payload, split into many packets.
        case packetCount
        /// Same tiny payload, one packet. The control arm for `packetCount`.
        case singleSegment

        public var label: String {
            switch self {
            case .byteAccumulation: "по объёму (накопление КБ)"
            case .packetCount: "по числу пакетов"
            case .singleSegment: "контроль: один сегмент"
            }
        }
    }

    /// What happened. `frozen` is the interesting one: the write went through,
    /// nothing came back, and no reset arrived.
    public enum Outcome: String, Sendable, Codable {
        case passed, frozen, failed
    }

    public let variant: Variant
    public let outcome: Outcome
    public let bytesSent: Int
    public let segmentsSent: Int
    public let elapsedMillis: Double
    public let failure: ProbeFailureKind?
    public let detail: String
}

/// The "16–20 КБ" check.
///
/// The user-facing name describes the symptom — connections to foreign hosts die
/// once a transfer gets going, historically around 16–20 KB. The measured cause
/// is not a byte threshold: it is a counter of roughly 25 packets in either
/// direction, and the connection **freezes silently without an RST**. Reported
/// thresholds range 14–34 KB precisely because packets, not bytes, are counted.
///
/// So the check runs three arms and reports what actually discriminates:
///  - `byteAccumulation` answers "at how many KB does it die?" (the familiar number)
///  - `packetCount` sends ~64 bytes as ~32 packets
///  - `singleSegment` sends the same ~64 bytes as one packet
///
/// A freeze in `packetCount` while `singleSegment` succeeds is a packet counter
/// and nothing else — 64 bytes of traffic has no benign reason to stall.
public struct TransferCutoffCheck: Sendable {
    /// ClientHello profile used for every arm of the check.
    public let fingerprint: TLSFingerprint

    public init(fingerprint: TLSFingerprint = .system) {
        self.fingerprint = fingerprint
    }

    /// Foreign-AS hosts where the behaviour is reported. Paired with a domestic
    /// control so "foreign freezes, domestic doesn't" can be stated.
    public static let defaultTarget = "cloudflare.com"
    public static let defaultControl = "yandex.ru"

    private static let padStep = 4000
    private static let maxPadStepCount = 15
    private static let tinyChunk = 2
    /// Just enough to keep the writes in separate segments. Longer gaps (the
    /// upstream tool uses 50 ms) look like slowloris to a CDN, which then closes
    /// the connection — and that would read as a freeze on a perfectly clean
    /// network. `TCP_NODELAY` is what actually guarantees the segmentation.
    private static let tinyChunkDelayMillis: UInt64 = 8

    // MARK: - Individual probes

    /// Variant A — grow the payload 4 KB at a time and report where it dies.
    public func probeByteAccumulation(
        host: String,
        port: UInt16 = 443,
        readTimeout: TimeInterval = 12
    ) async -> CutoffProbe {
        let start = MonoClock.nanos()
        var bytesSent = 0
        var segments = 0

        do {
            let endpoint = try await HostResolver.resolveFirst(host: host, port: port)
            let stream = try TLSStream(ip: endpoint.ipString, port: port, serverName: host, fingerprint: fingerprint)
            defer { stream.close() }
            try await stream.open(timeout: 8)

            // Payload goes in a POST body, not a header: servers cap header size
            // (Cloudflare rejects a 4 KB header outright), so header padding
            // measures the origin's limits rather than the network's.
            let total = Self.padStep * Self.maxPadStepCount
            let head = Array("""
            POST / HTTP/1.1\r
            Host: \(host)\r
            Content-Type: application/octet-stream\r
            Content-Length: \(total)\r
            Connection: keep-alive\r
            \r

            """.replacingOccurrences(of: "\n", with: "").utf8) + Array("\r\n\r\n".utf8)

            try await stream.send(head)
            segments += 1

            let chunk = [UInt8](repeating: 0x61, count: Self.padStep)
            for _ in 0..<Self.maxPadStepCount {
                try await stream.send(chunk)
                bytesSent += chunk.count
                segments += 1
            }

            // Any reply at all — even a 405 — proves the bytes crossed the network.
            let response = try await stream.receive(timeout: readTimeout)
            if response == nil {
                return CutoffProbe(
                    variant: .byteAccumulation, outcome: .failed,
                    bytesSent: bytesSent, segmentsSent: segments,
                    elapsedMillis: MonoClock.millisSince(start), failure: .eof,
                    detail: "сервер закрыл соединение после \(bytesSent / 1024) КБ"
                )
            }
            return CutoffProbe(
                variant: .byteAccumulation, outcome: .passed,
                bytesSent: bytesSent, segmentsSent: segments,
                elapsedMillis: MonoClock.millisSince(start), failure: nil,
                detail: "передано \(bytesSent / 1024) КБ без обрыва"
            )
        } catch {
            let kind = ProbeFailureKind.classify(error)
            // A silent stall is the signature. A clean close or a TLS alert is the
            // server talking back, and must not be reported as interference.
            let frozen = bytesSent > 0 && (kind == .timeout || kind == .reset)
            return CutoffProbe(
                variant: .byteAccumulation, outcome: frozen ? .frozen : .failed,
                bytesSent: bytesSent, segmentsSent: segments,
                elapsedMillis: MonoClock.millisSince(start), failure: kind,
                detail: frozen
                    ? "оборвалось на \(bytesSent / 1024) КБ — \(kind.label)"
                    : "не удалось выполнить пробу — \(kind.label)"
            )
        }
    }

    /// Variant B — a tiny request split into many packets.
    public func probePacketCount(
        host: String,
        port: UInt16 = 443,
        readTimeout: TimeInterval = 5
    ) async -> CutoffProbe {
        await probeTiny(host: host, port: port, chunked: true, readTimeout: readTimeout)
    }

    /// Variant C — the same tiny request as one packet.
    public func probeSingleSegment(
        host: String,
        port: UInt16 = 443,
        readTimeout: TimeInterval = 5
    ) async -> CutoffProbe {
        await probeTiny(host: host, port: port, chunked: false, readTimeout: readTimeout)
    }

    private func probeTiny(
        host: String, port: UInt16, chunked: Bool, readTimeout: TimeInterval
    ) async -> CutoffProbe {
        let variant: CutoffProbe.Variant = chunked ? .packetCount : .singleSegment
        let start = MonoClock.nanos()
        let request = Self.httpRequest(host: host, padding: 0)
        var segments = 0

        do {
            let endpoint = try await HostResolver.resolveFirst(host: host, port: port)
            let stream = try TLSStream(ip: endpoint.ipString, port: port, serverName: host, fingerprint: fingerprint)
            defer { stream.close() }
            try await stream.open(timeout: 8)

            if chunked {
                var offset = 0
                while offset < request.count {
                    let end = min(offset + Self.tinyChunk, request.count)
                    try await stream.send(Array(request[offset..<end]))
                    segments += 1
                    offset = end
                    if offset < request.count {
                        try await Task.sleep(for: .milliseconds(Self.tinyChunkDelayMillis))
                    }
                }
            } else {
                try await stream.send(request)
                segments = 1
            }

            let response = try await stream.receive(timeout: readTimeout)
            let elapsed = MonoClock.millisSince(start)
            if response == nil {
                return CutoffProbe(
                    variant: variant, outcome: .frozen, bytesSent: request.count,
                    segmentsSent: segments, elapsedMillis: elapsed, failure: .eof,
                    detail: "соединение закрыто после \(request.count) байт в \(segments) пакетах"
                )
            }
            return CutoffProbe(
                variant: variant, outcome: .passed, bytesSent: request.count,
                segmentsSent: segments, elapsedMillis: elapsed, failure: nil,
                detail: "ответ получен: \(request.count) байт в \(segments) пакетах"
            )
        } catch {
            let kind = ProbeFailureKind.classify(error)
            // Segments already left the device, so a stall here is a freeze.
            let outcome: CutoffProbe.Outcome = (segments > 0 && (kind == .timeout || kind == .reset)) ? .frozen : .failed
            return CutoffProbe(
                variant: variant, outcome: outcome, bytesSent: request.count,
                segmentsSent: segments, elapsedMillis: MonoClock.millisSince(start),
                failure: kind,
                detail: outcome == .frozen
                    ? "замерло на \(segments) пакетах (\(request.count) байт) — \(kind.label)"
                    : "не удалось выполнить пробу — \(kind.label)"
            )
        }
    }

    // MARK: - Full check

    /// Runs all three arms against `target`, plus the packet-count arm against
    /// `control`, and turns the combination into a verdict.
    public func run(
        target: String = TransferCutoffCheck.defaultTarget,
        control: String = TransferCutoffCheck.defaultControl
    ) async -> CensorshipFinding {
        let single = await probeSingleSegment(host: target)
        let packets = await probePacketCount(host: target)
        let bytes = await probeByteAccumulation(host: target)
        let controlPackets = await probePacketCount(host: control)

        var evidence = [
            "\(target): \(single.variant.label) → \(single.detail)",
            "\(target): \(packets.variant.label) → \(packets.detail)",
            "\(target): \(bytes.variant.label) → \(bytes.detail)",
            "\(control) (контроль): \(controlPackets.detail)"
        ]

        // Nothing to say if we couldn't establish a baseline at all.
        guard single.outcome != .failed || packets.outcome != .failed else {
            return CensorshipFinding(
                verdict: .inconclusive,
                headline: "Проверка не выполнена",
                detail: "Не удалось установить соединение с \(target). Возможно, сеть недоступна целиком.",
                evidence: evidence
            )
        }

        let packetCounterSuspected = packets.outcome == .frozen && single.outcome == .passed
        let byteThresholdSuspected = bytes.outcome == .frozen

        if packetCounterSuspected {
            evidence.append("Те же \(packets.bytesSent) байт одним сегментом прошли, а \(packets.segmentsSent) пакетами — нет.")
            if controlPackets.outcome == .passed {
                evidence.append("Российский контроль не затронут — ограничение зависит от назначения.")
            }
            return CensorshipFinding(
                verdict: .restricted,
                headline: "Соединение обрывают по числу пакетов",
                detail: "Мелкий запрос (\(packets.bytesSent) байт) прошёл одним пакетом, но замер, когда те же байты отправлены \(packets.segmentsSent) пакетами. Считаются пакеты, а не объём — обычная перегрузка сети так себя не ведёт."
                    + (byteThresholdSuspected ? " Обрыв по объёму зафиксирован на \(bytes.bytesSent / 1024) КБ." : ""),
                evidence: evidence
            )
        }

        if byteThresholdSuspected {
            return CensorshipFinding(
                verdict: .restricted,
                headline: "Передача обрывается на \(bytes.bytesSent / 1024) КБ",
                detail: "Соединение с \(target) замерло после \(bytes.bytesSent / 1024) КБ, хотя короткие запросы проходят. Пакетная проба обрыв не воспроизвела, поэтому порог похож на объёмный.",
                evidence: evidence
            )
        }

        return CensorshipFinding(
            verdict: .clean,
            headline: "Обрыв передачи не обнаружен",
            detail: "Все три пробы к \(target) дошли до конца: и короткий запрос по пакетам, и накопление до \(bytes.bytesSent / 1024) КБ.",
            evidence: evidence
        )
    }

    // MARK: - Helpers

    /// A minimal, valid keep-alive request — small on purpose, since the
    /// packet-count probe is about segmentation, not size.
    private static func httpRequest(host: String, padding: Int = 0) -> [UInt8] {
        Array("HEAD / HTTP/1.1\r\nHost: \(host)\r\nConnection: keep-alive\r\n\r\n".utf8)
    }
}
