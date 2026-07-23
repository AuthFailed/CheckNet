import Foundation

/// The censorship / local-restriction checks, and the orchestration that runs
/// each one.
///
/// This lives in NetworkKit, not the app, so that callers with no UI — App
/// Intents, the scheduler, background tasks — dispatch a check without importing
/// SwiftUI. The app layer keeps only presentation (titles, icons, explanations)
/// keyed on `rawValue`.
public enum CensorshipCheckKind: String, Sendable, CaseIterable, Codable {
    case dnsSpoofing, httpBlock, sniBlocking, ipBlocking, whitelist, siberian, transferCutoff

    /// Whether the check accepts a target host/domain (whitelist mode does not).
    public var needsTarget: Bool { self != .whitelist }

    /// The domain a check runs against when the user gives none. These are
    /// well-known probe targets: `transferCutoff` reuses the catalogue's foreign
    /// control host, the rest are domains commonly filtered in the target region.
    public var defaultTarget: String {
        switch self {
        case .dnsSpoofing, .httpBlock: return "rutracker.org"
        case .sniBlocking, .siberian:  return "www.tor-project.org"
        case .ipBlocking:              return "x.com"
        case .whitelist:               return ""
        case .transferCutoff:          return TransferCutoffCheck.defaultTarget
        }
    }

    /// Dispatches to the matching probe. Detection only — see the project's
    /// censorship policy; nothing here attempts to defeat a block.
    public func run(target: String) async -> CensorshipFinding {
        let checks = CensorshipChecks()
        let host = target.trimmingCharacters(in: .whitespaces)
        switch self {
        case .dnsSpoofing:    return await checks.checkDNSSpoofing(domain: host)
        case .httpBlock:      return await checks.checkHTTPBlockPage(domain: host)
        case .sniBlocking:    return await checks.checkSNIBlocking(blockedDomain: host)
        case .ipBlocking:     return await checks.checkIPBlocking(domain: host)
        case .whitelist:      return await checks.checkWhitelistMode()
        case .siberian:       return await checks.checkSiberianBlock(host: host)
        case .transferCutoff: return await TransferCutoffCheck().run(target: host)
        }
    }
}
