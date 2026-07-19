import Foundation
import Network

public struct BonjourService: Sendable, Hashable, Codable, Identifiable {
    public var id: String { "\(name)|\(type)|\(domain)" }
    public let name: String
    public let type: String
    public let domain: String

    /// Human-friendly label for a Bonjour service type.
    public var friendlyType: String {
        BonjourBrowser.knownTypes.first { $0.type == type }?.label ?? type
    }
}

/// Discovers Bonjour / mDNS services on the local network via NWBrowser,
/// browsing a curated set of common service types concurrently.
public final class BonjourBrowser: Sendable {
    public init() {}

    public struct ServiceType: Sendable, Hashable {
        public let type: String
        public let label: String
    }

    public static let knownTypes: [ServiceType] = [
        .init(type: "_http._tcp", label: "Веб (HTTP)"),
        .init(type: "_https._tcp", label: "Веб (HTTPS)"),
        .init(type: "_ssh._tcp", label: "SSH"),
        .init(type: "_sftp-ssh._tcp", label: "SFTP"),
        .init(type: "_smb._tcp", label: "SMB (общие папки)"),
        .init(type: "_afpovertcp._tcp", label: "AFP"),
        .init(type: "_airplay._tcp", label: "AirPlay"),
        .init(type: "_raop._tcp", label: "AirPlay Audio"),
        .init(type: "_googlecast._tcp", label: "Chromecast"),
        .init(type: "_ipp._tcp", label: "Принтер (IPP)"),
        .init(type: "_printer._tcp", label: "Принтер (LPD)"),
        .init(type: "_ipps._tcp", label: "Принтер (IPPS)"),
        .init(type: "_homekit._tcp", label: "HomeKit"),
        .init(type: "_hap._tcp", label: "HomeKit Accessory"),
        .init(type: "_spotify-connect._tcp", label: "Spotify Connect"),
        .init(type: "_device-info._tcp", label: "Информация об устройстве"),
        .init(type: "_companion-link._tcp", label: "Companion (Apple)"),
        .init(type: "_rfb._tcp", label: "Экран (VNC)")
    ]

    public enum BrowseEvent: Sendable {
        case found(BonjourService)
        case removed(BonjourService)
        case finished
    }

    /// Browses the given service types for `duration` seconds.
    public func browse(
        types: [ServiceType] = knownTypes,
        duration: TimeInterval = 6.0
    ) -> AsyncStream<BrowseEvent> {
        AsyncStream(bufferingPolicy: .unbounded) { continuation in
            let holder = BrowserHolder()
            let queue = DispatchQueue(label: "networkkit.bonjour")

            for st in types {
                let params = NWParameters()
                params.includePeerToPeer = true
                let browser = NWBrowser(for: .bonjour(type: st.type, domain: nil), using: params)
                browser.browseResultsChangedHandler = { results, changes in
                    for change in changes {
                        switch change {
                        case .added(let result):
                            if let svc = Self.service(from: result) {
                                continuation.yield(.found(svc))
                            }
                        case .removed(let result):
                            if let svc = Self.service(from: result) {
                                continuation.yield(.removed(svc))
                            }
                        default:
                            break
                        }
                    }
                }
                browser.start(queue: queue)
                holder.add(browser)
            }

            queue.asyncAfter(deadline: .now() + duration) {
                holder.cancelAll()
                continuation.yield(.finished)
                continuation.finish()
            }

            continuation.onTermination = { _ in holder.cancelAll() }
        }
    }

    private static func service(from result: NWBrowser.Result) -> BonjourService? {
        if case let .service(name, type, domain, _) = result.endpoint {
            return BonjourService(name: name, type: type, domain: domain)
        }
        return nil
    }
}

/// Retains the active NWBrowsers so they aren't deallocated mid-browse.
private final class BrowserHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var browsers: [NWBrowser] = []
    private var cancelled = false

    func add(_ b: NWBrowser) {
        lock.lock(); defer { lock.unlock() }
        if cancelled { b.cancel() } else { browsers.append(b) }
    }
    func cancelAll() {
        lock.lock(); let list = browsers; browsers = []; cancelled = true; lock.unlock()
        for b in list { b.cancel() }
    }
}
