import Foundation
import Network

/// How a probe ended. The distinction matters: a reset means something on the
/// path injected an RST, a silent timeout means it dropped the packets, and a
/// TLS alert means the *server* refused us — which is not interference at all.
///
/// Mirrors the failure vocabulary OONI uses, so results stay comparable with
/// published measurements.
public enum ProbeFailureKind: String, Sendable, Codable {
    /// `ECONNRESET` — an RST arrived.
    case reset
    /// Nothing came back before the deadline.
    case timeout
    /// The peer closed cleanly mid-exchange.
    case eof
    /// `ECONNREFUSED` — reached the host, nothing listening.
    case refused
    /// Host or network unreachable — routing, not filtering.
    case unreachable
    /// The TLS handshake produced an alert. Server-side, **not** censorship.
    case tlsAlert
    case other

    public var label: String {
        switch self {
        case .reset: "соединение сброшено (RST)"
        case .timeout: "нет ответа (тихий обрыв)"
        case .eof: "соединение закрыто"
        case .refused: "подключение отклонено"
        case .unreachable: "сеть недоступна"
        case .tlsAlert: "TLS-ошибка на стороне сервера"
        case .other: "другая ошибка"
        }
    }

    /// True when the failure could plausibly be interference rather than a
    /// server-side or routing problem.
    public var suggestsInterference: Bool {
        switch self {
        case .reset, .timeout, .eof: true
        case .refused, .unreachable, .tlsAlert, .other: false
        }
    }

    public static func classify(_ error: Error) -> ProbeFailureKind {
        if let nw = error as? NWError { return classify(nw) }
        if let net = error as? NetworkError {
            switch net {
            case .timedOut: return .timeout
            case .tls: return .tlsAlert
            default: return .other
            }
        }
        return .other
    }

    public static func classify(_ error: NWError) -> ProbeFailureKind {
        switch error {
        case .posix(let code):
            switch code {
            case .ECONNRESET: return .reset
            case .ECONNREFUSED: return .refused
            case .ETIMEDOUT: return .timeout
            case .EHOSTUNREACH, .ENETUNREACH, .ENETDOWN: return .unreachable
            case .ECONNABORTED: return .eof
            default: return .other
            }
        case .tls: return .tlsAlert
        default: return .other
        }
    }
}
