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
        case .invalidHost(let h): return "Invalid host: \(h)"
        case .resolutionFailed(let h, let r): return "Failed to resolve \(h): \(r)"
        case .socketCreationFailed(let r): return "Failed to create socket: \(r)"
        case .socketOptionFailed(let r): return "Socket setup error: \(r)"
        case .sendFailed(let r): return "Send error: \(r)"
        case .timedOut: return "Timed out"
        case .cancelled: return "Cancelled"
        case .notSupported(let m): return "Not supported: \(m)"
        case .tls(let m): return "TLS error: \(m)"
        case .protocolError(let m): return "Protocol error: \(m)"
        }
    }
}

/// IP address family for a resolved endpoint.
public enum IPFamily: String, Sendable, Codable, Hashable {
    case ipv4
    case ipv6
}
