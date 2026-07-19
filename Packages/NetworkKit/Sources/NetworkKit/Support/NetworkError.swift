import Foundation

/// Errors surfaced by NetworkKit engines. Messages are user-presentable.
public enum NetworkError: Error, LocalizedError, Sendable, Equatable {
    case invalidHost(String)
    case resolutionFailed(host: String, reason: String)
    case socketCreationFailed(reason: String)
    case socketOptionFailed(reason: String)
    case sendFailed(reason: String)
    case timedOut
    case cancelled
    case notSupported(String)
    case tls(String)
    case protocolError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidHost(let h): return "Некорректный хост: \(h)"
        case .resolutionFailed(let h, let r): return "Не удалось разрешить \(h): \(r)"
        case .socketCreationFailed(let r): return "Не удалось создать сокет: \(r)"
        case .socketOptionFailed(let r): return "Ошибка настройки сокета: \(r)"
        case .sendFailed(let r): return "Ошибка отправки: \(r)"
        case .timedOut: return "Истекло время ожидания"
        case .cancelled: return "Отменено"
        case .notSupported(let m): return "Не поддерживается: \(m)"
        case .tls(let m): return "Ошибка TLS: \(m)"
        case .protocolError(let m): return "Ошибка протокола: \(m)"
        }
    }
}

/// IP address family for a resolved endpoint.
public enum IPFamily: String, Sendable, Codable, Hashable {
    case ipv4
    case ipv6
}
