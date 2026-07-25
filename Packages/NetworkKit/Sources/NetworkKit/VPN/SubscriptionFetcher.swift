import Foundation

/// A client identity to request a subscription as. Panels serve different
/// content (or a 403 page) depending on the `User-Agent`.
public struct SubscriptionUserAgent: Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public let label: String
    /// The `User-Agent` header; `nil` means Auto (try several in order).
    public let header: String?

    public init(id: String, label: String, header: String?) {
        self.id = id; self.label = label; self.header = header
    }
}

public enum SubscriptionUserAgents {
    public static let auto = SubscriptionUserAgent(id: "auto", label: "Авто", header: nil)

    /// Auto and the concrete clients, ordered popular → niche. Auto walks the
    /// concrete headers below until one returns a parseable node list.
    public static let all: [SubscriptionUserAgent] = [
        auto,
        .init(id: "v2rayng", label: "v2rayNG", header: "v2rayNG/1.9.5"),
        .init(id: "happ", label: "Happ", header: "Happ/5.2.0"),
        .init(id: "clashmeta", label: "Clash Meta", header: "clash-verge/2.0.3"),
        .init(id: "singbox", label: "sing-box", header: "sing-box/1.11.0"),
        .init(id: "hiddify", label: "Hiddify", header: "Hiddify/2.5.7"),
        .init(id: "streisand", label: "Streisand", header: "Streisand/1.6.44"),
        .init(id: "shadowrocket", label: "Shadowrocket", header: "Shadowrocket/2.2.35"),
        .init(id: "nekobox", label: "NekoBox", header: "NekoBox/1.3.5"),
        .init(id: "v2box", label: "V2Box", header: "V2Box/1.9.0"),
        .init(id: "karing", label: "Karing", header: "Karing/1.2.22"),
    ]

    /// Concrete headers to try in Auto mode, most popular first.
    public static var autoOrder: [String] { all.compactMap(\.header) }
}

/// Fetches subscription content over HTTP with a chosen (or auto-tried) client
/// `User-Agent`, then parses it.
public enum SubscriptionFetcher {
    public struct Outcome: Sendable {
        public let result: SubscriptionParser.Result
        /// The `User-Agent` that produced the content (nil if none worked).
        public let userAgent: String?
        public let content: String
    }

    public enum FetchError: Error, Sendable { case badURL, empty, http(Int) }

    /// Fetch with a specific `User-Agent` and parse. `userAgent == nil` runs Auto.
    public static func fetchAndParse(_ urlString: String, userAgent: String?) async throws -> Outcome {
        guard let url = URL(string: urlString) else { throw FetchError.badURL }
        if let userAgent {
            let content = try await fetch(url, userAgent: userAgent)
            return Outcome(result: SubscriptionParser.parse(content), userAgent: userAgent, content: content)
        }
        return try await auto(url)
    }

    /// Try each Auto UA until one parses to at least one node; else return the
    /// last attempt so the caller can still show what came back.
    private static func auto(_ url: URL) async throws -> Outcome {
        var last: Outcome?
        for ua in SubscriptionUserAgents.autoOrder {
            guard let content = try? await fetch(url, userAgent: ua) else { continue }
            let parsed = SubscriptionParser.parse(content)
            let outcome = Outcome(result: parsed, userAgent: ua, content: content)
            if !parsed.nodes.isEmpty { return outcome }
            last = outcome
        }
        if let last { return last }
        throw FetchError.empty
    }

    private static func fetch(_ url: URL, userAgent: String) async throws -> String {
        var req = URLRequest(url: url)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("clash.meta", forHTTPHeaderField: "Accept")   // some panels key on this too
        req.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw FetchError.http(http.statusCode)
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
