import Foundation

/// Wire format for sharing saved hosts between devices.
///
/// A share link looks like `checknet://hosts?d=<base64url>`, where the payload is
/// deflated JSON. Deflating keeps a couple of dozen hosts well inside the byte
/// capacity of a QR code even with Cyrillic names.
enum HostSharing {
    static let scheme = "checknet"
    static let hostsAction = "hosts"

    /// Guards against a hostile link flooding the store.
    static let maxHosts = 500

    private struct Payload: Codable {
        var v: Int
        var h: [Item]
        struct Item: Codable {
            var n: String   // display name
            var a: String   // address (IP or domain)
        }
    }

    // MARK: - Encoding

    /// Builds a share link for `hosts`, or nil if there is nothing to share.
    static func url(for hosts: [SavedHost]) -> URL? {
        guard !hosts.isEmpty else { return nil }
        let payload = Payload(v: 1, h: hosts.map { .init(n: $0.name, a: $0.value) })
        guard let json = try? JSONEncoder().encode(payload) else { return nil }
        // Fall back to raw JSON if deflate fails; the decoder sniffs both.
        let body = (try? (json as NSData).compressed(using: .zlib) as Data) ?? json

        var components = URLComponents()
        components.scheme = scheme
        components.host = hostsAction
        components.queryItems = [URLQueryItem(name: "d", value: base64url(body))]
        return components.url
    }

    // MARK: - Decoding

    /// Parses a share link back into hosts. Returns nil for anything that isn't
    /// a well-formed CheckNet host link.
    static func hosts(from url: URL) -> [SavedHost]? {
        guard url.scheme?.lowercased() == scheme,
              url.host?.lowercased() == hostsAction,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let encoded = components.queryItems?.first(where: { $0.name == "d" })?.value,
              let raw = data(base64url: encoded)
        else { return nil }

        let json = (try? (raw as NSData).decompressed(using: .zlib) as Data) ?? raw
        guard let payload = try? JSONDecoder().decode(Payload.self, from: json), payload.v == 1 else { return nil }

        return payload.h.prefix(maxHosts).compactMap { item in
            let value = item.a.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isPlausibleTarget(value) else { return nil }
            let name = item.n.trimmingCharacters(in: .whitespacesAndNewlines)
            return SavedHost(name: name.isEmpty ? value : String(name.prefix(64)), value: value, toolID: nil)
        }
    }

    /// Finds a CheckNet link inside arbitrary pasted text (users often copy a
    /// link along with surrounding words).
    static func hosts(fromPastedText text: String) -> [SavedHost]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), let hosts = hosts(from: url) { return hosts }
        guard let range = trimmed.range(of: "\(scheme)://\(hostsAction)?", options: .caseInsensitive) else { return nil }
        let tail = trimmed[range.lowerBound...].prefix { !$0.isWhitespace }
        guard let url = URL(string: String(tail)) else { return nil }
        return hosts(from: url)
    }

    /// Accepts IP literals and plausible domain names, rejects everything else.
    private static func isPlausibleTarget(_ value: String) -> Bool {
        guard (1...253).contains(value.count) else { return false }
        if IPAddress.isValid(value) { return true }
        guard value.contains("."), !value.contains(" ") else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_")
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    // MARK: - base64url

    private static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func data(base64url string: String) -> Data? {
        var s = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        s += String(repeating: "=", count: (4 - s.count % 4) % 4)
        return Data(base64Encoded: s)
    }
}
