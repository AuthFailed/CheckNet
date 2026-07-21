import Foundation

/// Whether the network is intercepting traffic before the user has signed in.
public struct CaptivePortalResult: Sendable, Hashable {
    public enum State: String, Sendable, Codable {
        /// The known probe endpoint answered exactly as expected — open network.
        case open
        /// The probe was redirected or rewritten — a portal is in the way.
        case captive
        /// Couldn't reach the probe at all; can't tell.
        case unknown

        public var label: String {
            switch self {
            case .open: "сеть открыта"
            case .captive: "требуется вход (captive portal)"
            case .unknown: "не удалось определить"
            }
        }
    }

    public let state: State
    public let detail: String
    /// Where the portal sends the user, when detectable.
    public let redirectURL: String?
}

/// Detects a captive portal — the hotel/airport "sign in to continue" page.
///
/// This must run **before** any censorship check: a portal rewrites every
/// request, so without this gate a captive network lights up every block
/// detector as a false positive.
public struct CaptivePortalCheck: Sendable {
    public init() {}

    /// Apple's own captive-portal probe. A clean network returns this body over
    /// plain HTTP verbatim; anything else means something is intercepting.
    static let probeHost = "captive.apple.com"
    static let probePath = "/hotspot-detect.html"
    static let expectedBody = "<HTML><HEAD><TITLE>Success</TITLE></HEAD><BODY>Success</BODY></HTML>"

    public func run(timeout: TimeInterval = 6) async -> CaptivePortalResult {
        do {
            let endpoint = try await HostResolver.resolveFirst(host: Self.probeHost, port: 80)
            return try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(returning: Self.probeBlocking(endpoint: endpoint, timeout: timeout))
                }
            }
        } catch {
            return CaptivePortalResult(
                state: .unknown,
                detail: "Не удалось обратиться к \(Self.probeHost).",
                redirectURL: nil
            )
        }
    }

    private static func probeBlocking(endpoint: ResolvedEndpoint, timeout: TimeInterval) -> CaptivePortalResult {
        let request = Array((
            "GET \(probePath) HTTP/1.1\r\n" +
            "Host: \(probeHost)\r\n" +
            "User-Agent: CaptiveNetworkSupport\r\n" +
            "Connection: close\r\n\r\n"
        ).utf8)

        let raw: [UInt8]
        do {
            let (fd, _) = try TCPTransport.connect(endpoint: endpoint, timeout: timeout)
            defer { close(fd) }
            try TCPTransport.writeAll(fd: fd, bytes: request)
            raw = try TCPTransport.readUntilClose(fd: fd, timeout: timeout, maxBytes: 64 * 1024)
        } catch {
            return CaptivePortalResult(state: .unknown, detail: "Проба не завершилась.", redirectURL: nil)
        }

        let response = String(decoding: raw, as: UTF8.self)
        guard let headerEnd = response.range(of: "\r\n\r\n") else {
            return CaptivePortalResult(state: .unknown, detail: "Пустой ответ.", redirectURL: nil)
        }
        let head = String(response[..<headerEnd.lowerBound])
        let body = String(response[headerEnd.upperBound...])
        let statusLine = head.split(separator: "\r\n").first.map(String.init) ?? ""

        // A redirect is the textbook portal signature.
        if statusLine.contains(" 30") {
            let location = head.split(separator: "\r\n")
                .first { $0.lowercased().hasPrefix("location:") }
                .map { $0.dropFirst("location:".count).trimmingCharacters(in: .whitespaces) }
            return CaptivePortalResult(
                state: .captive,
                detail: "Сеть перенаправляет запросы — вероятно, нужен вход через страницу авторизации.",
                redirectURL: location
            )
        }

        if body.contains(Self.expectedBody) {
            return CaptivePortalResult(
                state: .open,
                detail: "Контрольная страница вернулась без изменений — перехвата нет.",
                redirectURL: nil
            )
        }

        // 200 OK but a different body means the portal answered in place.
        return CaptivePortalResult(
            state: .captive,
            detail: "Ответ отличается от эталонного — содержимое подменяется.",
            redirectURL: nil
        )
    }
}
