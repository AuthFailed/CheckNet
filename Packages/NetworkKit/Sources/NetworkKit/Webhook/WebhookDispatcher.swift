import Foundation
import CryptoKit

/// What happened, in a shape a receiving server can rely on.
///
/// Field names and the envelope are the app's public contract — see
/// `docs/webhooks.md`. Changing them breaks other people's integrations, so
/// `version` is carried explicitly.
public struct WebhookEvent: Sendable, Codable {
    public static let currentVersion = 1

    public let version: Int
    /// Dotted event name, e.g. `check.ping` or `blocking.transferCutoff`.
    public let event: String
    public let timestamp: Date
    public let host: String
    public let succeeded: Bool
    public let verdict: String?
    public let headline: String?
    public let detail: String?
    public let latencyMillis: Double?
    public let lossPercent: Double?
    /// Free-form extras; kept separate so the top level stays stable.
    public let metadata: [String: String]?

    public init(
        event: String,
        timestamp: Date = Date(),
        host: String,
        succeeded: Bool,
        verdict: String? = nil,
        headline: String? = nil,
        detail: String? = nil,
        latencyMillis: Double? = nil,
        lossPercent: Double? = nil,
        metadata: [String: String]? = nil
    ) {
        self.version = Self.currentVersion
        self.event = event
        self.timestamp = timestamp
        self.host = host
        self.succeeded = succeeded
        self.verdict = verdict
        self.headline = headline
        self.detail = detail
        self.latencyMillis = latencyMillis
        self.lossPercent = lossPercent
        self.metadata = metadata
    }
}

public struct WebhookDelivery: Sendable {
    public let statusCode: Int?
    public let attempts: Int
    public let error: String?
    public var succeeded: Bool { (statusCode ?? 0) / 100 == 2 }
}

/// Posts events to a user-supplied endpoint.
///
/// Sending measurement results off the device is a disclosure, so this only
/// ever runs against an address the user typed, and the payload carries exactly
/// the fields documented — nothing is silently added.
public struct WebhookDispatcher: Sendable {
    public enum DispatchError: Error, Sendable {
        case invalidURL
        case insecureScheme
    }

    public let url: URL
    /// Optional shared secret. When set, each request is signed so the receiver
    /// can verify it actually came from this device.
    public let secret: String?
    public let maxAttempts: Int
    public let timeout: TimeInterval

    public init(url: URL, secret: String? = nil, maxAttempts: Int = 3, timeout: TimeInterval = 10) {
        self.url = url
        self.secret = secret
        self.maxAttempts = max(1, maxAttempts)
        self.timeout = timeout
    }

    /// Validates a user-entered endpoint. Plain `http` is rejected outside
    /// loopback — results would otherwise cross the network in the clear.
    public static func validate(urlString: String, allowInsecure: Bool = false) throws -> URL {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), url.host != nil else {
            throw DispatchError.invalidURL
        }
        guard scheme == "https" || scheme == "http" else { throw DispatchError.invalidURL }
        if scheme == "http" && !allowInsecure {
            let host = url.host?.lowercased() ?? ""
            let isLoopback = host == "localhost" || host == "127.0.0.1" || host == "::1"
            guard isLoopback else { throw DispatchError.insecureScheme }
        }
        return url
    }

    public static func encode(_ event: WebhookEvent) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(event)
    }

    /// `HMAC-SHA256(secret, body)`, lowercase hex — the shape most webhook
    /// receivers already know how to verify.
    public static func signature(body: Data, secret: String) -> String {
        let key = SymmetricKey(data: Data(secret.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: body, using: key)
        return mac.map { String(format: "%02x", $0) }.joined()
    }

    @discardableResult
    public func send(_ event: WebhookEvent) async -> WebhookDelivery {
        let body: Data
        do {
            body = try Self.encode(event)
        } catch {
            return WebhookDelivery(statusCode: nil, attempts: 0, error: "не удалось сформировать payload")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("CheckNet/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue(event.event, forHTTPHeaderField: "X-CheckNet-Event")
        request.setValue(String(WebhookEvent.currentVersion), forHTTPHeaderField: "X-CheckNet-Version")
        if let secret, !secret.isEmpty {
            request.setValue("sha256=" + Self.signature(body: body, secret: secret),
                             forHTTPHeaderField: "X-CheckNet-Signature")
        }
        request.httpBody = body

        var lastError: String?
        for attempt in 1...maxAttempts {
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                let code = (response as? HTTPURLResponse)?.statusCode
                if let code, (200..<300).contains(code) {
                    return WebhookDelivery(statusCode: code, attempts: attempt, error: nil)
                }
                // 4xx means the receiver rejected the payload; retrying won't fix it.
                if let code, (400..<500).contains(code) {
                    return WebhookDelivery(statusCode: code, attempts: attempt, error: "получен ответ \(code)")
                }
                lastError = code.map { "получен ответ \($0)" } ?? "нет ответа"
            } catch {
                lastError = error.localizedDescription
            }
            if attempt < maxAttempts {
                // Back off so a struggling receiver isn't hammered.
                try? await Task.sleep(for: .milliseconds(300 * attempt * attempt))
            }
        }
        return WebhookDelivery(statusCode: nil, attempts: maxAttempts, error: lastError)
    }
}
