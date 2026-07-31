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
    static let isSSIDReadable = true

    enum Result: Sendable, Equatable {
        /// Connected to Wi-Fi — the App-Store-safe identity iOS exposes
        /// (SSID/BSSID/security). RF metrics aren't available to apps on iOS.
        case connected(WiFiIdentity)
        /// Connected to Wi-Fi, but the SSID is withheld (permission/entitlement).
        case restricted(reason: String)
        /// Not on Wi-Fi, or the platform can't report it.
        case unavailable(reason: String)
    }

    static func current() async -> Result {
        #if os(iOS)
        guard isSSIDReadable else {
            return .unavailable(reason: "This build is not entitled to read the Wi-Fi network name.")
        }

        // Location permission is a prerequisite; request it if undetermined.
        let status = await LocationGate.shared.authorize()
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            break
        case .notDetermined:
            return .restricted(reason: "Location permission has not been granted.")
        default:
            return .restricted(reason: "Location access is denied — iOS does not reveal the network name.")
        }

        return await withCheckedContinuation { continuation in
            NEHotspotNetwork.fetchCurrent { network in
                if let network {
                    let security: WiFiIdentity.Security
                    switch network.securityType {
                    case .open: security = .open
                    case .WEP: security = .wep
                    case .personal: security = .personal
                    case .enterprise: security = .enterprise
                    case .unknown: security = .unknown
                    @unknown default: security = .unknown
                    }
                    let info = WiFiIdentity(ssid: network.ssid, bssid: network.bssid,
                                            security: security)
                    continuation.resume(returning: .connected(info))
                } else {
                    // No network object means either not on Wi-Fi or the app
                    // lacks the Access Wi-Fi Information entitlement.
                    continuation.resume(returning: .unavailable(
                        reason: "No access to the network name. The app needs the Wi-Fi entitlement and an active Wi-Fi connection."
                    ))
                }
            }
        }
        #else
        return .unavailable(reason: "Network detection is available on iOS only.")
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
