import Foundation

/// Deep links the user-added Control Center / Lock Screen controls use to jump
/// into the app. The controls (widget extension) build these URLs; the app
/// resolves them in `onOpenURL`. Kept pure and in `Shared/` so both processes
/// share one grammar and it can be unit-tested.
///
/// Forms:
///   `checknet://tool/<toolRawValue>?host=<h>&run=1`
///   `checknet://tab/<name>`   (name: tests · blocking · settings)
enum ControlDeepLink {
    static let scheme = "checknet"

    enum Target: Equatable {
        case tool(raw: String, host: String?, run: Bool)
        case tab(String)
    }

    // MARK: Building (widget side)

    static func toolURL(_ toolRawValue: String, host: String? = nil, run: Bool = false) -> URL? {
        var comps = URLComponents()
        comps.scheme = scheme
        comps.host = "tool"
        comps.path = "/" + toolRawValue
        var items: [URLQueryItem] = []
        if let host, !host.isEmpty { items.append(URLQueryItem(name: "host", value: host)) }
        if run { items.append(URLQueryItem(name: "run", value: "1")) }
        if !items.isEmpty { comps.queryItems = items }
        return comps.url
    }

    static func tabURL(_ name: String) -> URL? {
        var comps = URLComponents()
        comps.scheme = scheme
        comps.host = "tab"
        comps.path = "/" + name
        return comps.url
    }

    // MARK: Resolving (app side)

    static func target(from url: URL) -> Target? {
        guard url.scheme == scheme else { return nil }
        let segment = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        switch url.host {
        case "tool":
            guard !segment.isEmpty else { return nil }
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let host = items.first { $0.name == "host" }?.value
            let run = items.first { $0.name == "run" }?.value == "1"
            return .tool(raw: segment, host: (host?.isEmpty ?? true) ? nil : host, run: run)
        case "tab":
            guard !segment.isEmpty else { return nil }
            return .tab(segment)
        default:
            return nil
        }
    }
}

/// One-line summary a ping control shows at a glance, from the last stored
/// result. Pure so the phrasing is unit-tested rather than eyeballed in
/// Control Center.
enum ControlSnapshotDisplay {
    static func subtitle(_ snapshot: PingSnapshot) -> String {
        switch snapshot.status {
        case .down:
            return snapshot.statusLabel          // "Недоступен"
        case .unknown:
            return snapshot.statusLabel          // "—"
        case .ok, .degraded:
            if let ms = snapshot.latencyMillis {
                return "\(Int(ms.rounded())) мс"
            }
            return snapshot.statusLabel
        }
    }
}
