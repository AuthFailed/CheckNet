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
    private static let tinyChunkDelayMillis: UInt64 = 50

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

            // i = 0 is the liveness control: if an unpadded request fails, the
            // host is simply unreachable and the run proves nothing.
            for i in 0...Self.maxPadStepCount {
                let request = Self.httpRequest(host: host, padding: i == 0 ? 0 : Self.padStep)
                try await stream.send(request)
                bytesSent += request.count
                segments += 1

                let response = try await stream.receive(timeout: readTimeout)
                if response == nil {
                    return CutoffProbe(
                        variant: .byteAccumulation, outcome: i == 0 ? .failed : .frozen,
                        bytesSent: bytesSent, segmentsSent: segments,
                        elapsedMillis: MonoClock.millisSince(start), failure: .eof,
                        detail: "соединение закрыто после \(bytesSent / 1024) КБ"
                    )
                }
            }

            return CutoffProbe(
                variant: .byteAccumulation, outcome: .passed,
                bytesSent: bytesSent, segmentsSent: segments,
                elapsedMillis: MonoClock.millisSince(start), failure: nil,
                detail: "передано \(bytesSent / 1024) КБ без обрыва"
            )
        } catch {
            let kind = ProbeFailureKind.classify(error)
            // A stall after the unpadded control succeeded is the signature.
            let outcome: CutoffProbe.Outcome = (bytesSent > 0 && kind.suggestsInterference) ? .frozen : .failed
            return CutoffProbe(
                variant: .byteAccumulation, outcome: outcome,
                bytesSent: bytesSent, segmentsSent: segments,
                elapsedMillis: MonoClock.millisSince(start), failure: kind,
                detail: outcome == .frozen
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
            let outcome: CutoffProbe.Outcome = (segments > 0 && kind.suggestsInterference) ? .frozen : .failed
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

    /// A minimal, valid keep-alive request. `padding` bytes of filler go into a
    /// custom header so the size is ours to choose.
    private static func httpRequest(host: String, padding: Int) -> [UInt8] {
        var request = "HEAD / HTTP/1.1\r\nHost: \(host)\r\nConnection: keep-alive\r\n"
        if padding > 0 {
            request += "X-Pad: " + String(repeating: "a", count: padding) + "\r\n"
        }
        request += "\r\n"
        return Array(request.utf8)
    }
}
