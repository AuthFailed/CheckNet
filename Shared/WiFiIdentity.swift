import Foundation

/// Identity of the Wi-Fi network the device is currently on — the subset iOS
/// exposes to apps through `NEHotspotNetwork` (SSID, BSSID, security type).
///
/// iOS has **no public API** for RF metrics (RSSI in dBm, channel, band, or a
/// scan of neighbouring networks); those require private frameworks that App
/// Review rejects, so they stay in the macOS Wi-Fi tools (CoreWLAN). This type
/// carries only what an App-Store build can honestly show on iOS.
///
/// Pure and `Sendable` so the formatting is unit-tested without a device.
struct WiFiIdentity: Sendable, Equatable {
    enum Security: Sendable, Equatable {
        case open, wep, personal, enterprise, unknown
    }

    let ssid: String
    let bssid: String?
    let security: Security

    init(ssid: String, bssid: String? = nil, security: Security = .unknown) {
        self.ssid = ssid
        let trimmed = bssid?.trimmingCharacters(in: .whitespaces)
        self.bssid = (trimmed?.isEmpty ?? true) ? nil : trimmed
        self.security = security
    }

    /// Open networks send traffic in the clear; everything else is encrypted.
    var isSecure: Bool { security != .open }

    /// Localizable label for the security type. Russian literals double as the
    /// String Catalog keys (see the localization notes in CLAUDE.md).
    var securityLabel: String {
        switch security {
        case .open: "Open (unencrypted)"
        case .wep: "WEP"
        case .personal: "WPA/WPA2/WPA3 Personal"
        case .enterprise: "Enterprise (802.1X)"
        case .unknown: "Unknown"
        }
    }

    /// BSSID normalised for display: lowercase, colon-separated, each octet
    /// zero-padded to two hex digits. iOS returns octets without leading zeros
    /// ("0:23:a:..") — normalise so the MAC reads consistently.
    var bssidDisplay: String? {
        guard let bssid else { return nil }
        let parts = bssid.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 6 else { return bssid.lowercased() }
        return parts.map { octet in
            let hex = octet.lowercased()
            return hex.count == 1 ? "0\(hex)" : String(hex)
        }.joined(separator: ":")
    }
}
