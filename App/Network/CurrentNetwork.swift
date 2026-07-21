import Foundation
#if os(iOS)
import NetworkExtension
import CoreLocation
#endif

/// Reads the SSID of the Wi-Fi network the device is currently on.
///
/// Per Apple's documentation this needs two things that only line up on a real,
/// properly provisioned device:
///  1. the **Access Wi-Fi Information** capability
///     (`com.apple.developer.networking.wifi-info` entitlement), and
///  2. **When In Use** location authorization — since iOS 13 the current SSID
///     is treated as location-adjacent data.
///
/// `NEHotspotNetwork.fetchCurrent(completionHandler:)` returns the network only
/// when both are satisfied. Until the entitlement is available this resolves to
/// `.unavailable` with the reason, rather than failing silently.
enum CurrentNetwork {
    /// Whether the build carries **Access Wi-Fi Information**.
    ///
    /// The entitlement can only be signed by a paid developer account, so it is
    /// currently commented out in `App/CheckNet.entitlements`. This flag is the
    /// code-side half of that switch: flip both together, never one alone.
    ///
    /// Without it `NEHotspotNetwork.fetchCurrent` always reports no network, so
    /// the app must not pretend otherwise — and must not ask for location, which
    /// is only a prerequisite for a lookup that cannot succeed.
    static let isSSIDReadable = false

    enum Result: Sendable, Equatable {
        case ssid(String)
        /// Connected to Wi-Fi, but the SSID is withheld (permission/entitlement).
        case restricted(reason: String)
        /// Not on Wi-Fi, or the platform can't report it.
        case unavailable(reason: String)
    }

    static func current() async -> Result {
        #if os(iOS)
        guard isSSIDReadable else {
            return .unavailable(reason: "У сборки нет прав на чтение имени Wi-Fi-сети.")
        }

        // Location permission is a prerequisite; request it if undetermined.
        let status = await LocationGate.shared.authorize()
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            break
        case .notDetermined:
            return .restricted(reason: "Не выдано разрешение на геопозицию.")
        default:
            return .restricted(reason: "Доступ к геопозиции запрещён — имя сети iOS не отдаёт.")
        }

        return await withCheckedContinuation { continuation in
            NEHotspotNetwork.fetchCurrent { network in
                if let network {
                    continuation.resume(returning: .ssid(network.ssid))
                } else {
                    // No network object means either not on Wi-Fi or the app
                    // lacks the Access Wi-Fi Information entitlement.
                    continuation.resume(returning: .unavailable(
                        reason: "Нет доступа к имени сети. Нужны Wi-Fi-права приложения и подключение к Wi-Fi."
                    ))
                }
            }
        }
        #else
        return .unavailable(reason: "Определение сети доступно только на iOS.")
        #endif
    }
}

#if os(iOS)
/// Serialises the one-shot location-permission request behind an async call.
private final class LocationGate: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    static let shared = LocationGate()

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLAuthorizationStatus, Never>?

    override init() {
        super.init()
        manager.delegate = self
    }

    func authorize() async -> CLAuthorizationStatus {
        let current = manager.authorizationStatus
        guard current == .notDetermined else { return current }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager.requestWhenInUseAuthorization()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager.authorizationStatus != .notDetermined else { return }
        continuation?.resume(returning: manager.authorizationStatus)
        continuation = nil
    }
}
#endif
