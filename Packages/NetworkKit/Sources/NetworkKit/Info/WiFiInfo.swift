#if canImport(CoreWLAN)
import Foundation
import CoreWLAN

/// Wi-Fi radio details and a scan of neighbouring networks, via CoreWLAN.
/// macOS only — iOS doesn't expose channels, RSSI or a scan to apps, which is
/// why the iOS build keeps these tools as "available on Mac" placeholders.
///
/// The RF metrics of the current link (RSSI, noise, channel, rate, PHY mode)
/// read without any permission; the network's SSID/BSSID and a full scan need
/// Location access on modern macOS.
public struct WiFiInfo: Sendable {
    public init() {}

    /// The current link's status, or nil if Wi-Fi is off / no interface.
    public func current() -> WiFiStatus? {
        guard let iface = CWWiFiClient.shared().interface() else { return nil }
        let channel = iface.wlanChannel()
        return WiFiStatus(
            ssid: iface.ssid(),
            bssid: iface.bssid(),
            rssi: iface.rssiValue(),
            noise: iface.noiseMeasurement(),
            txRateMbps: iface.transmitRate(),
            channel: channel?.channelNumber ?? 0,
            band: WiFiBand(channel?.channelBand),
            width: WiFiWidth(channel?.channelWidth),
            phyMode: WiFiPHYMode(iface.activePHYMode()),
            interfaceName: iface.interfaceName ?? "Wi-Fi"
        )
    }

    /// Scan for nearby networks. Needs Location access on modern macOS; throws
    /// or returns empty otherwise.
    public func scan() async throws -> [WiFiNetwork] {
        guard let iface = CWWiFiClient.shared().interface() else { return [] }
        let currentBSSID = iface.bssid()
        let networks = try iface.scanForNetworks(withSSID: nil)
        return networks.map { network in
            let channel = network.wlanChannel
            return WiFiNetwork(
                ssid: network.ssid,
                bssid: network.bssid,
                rssi: network.rssiValue,
                channel: channel?.channelNumber ?? 0,
                band: WiFiBand(channel?.channelBand),
                width: WiFiWidth(channel?.channelWidth),
                isSecure: !network.supportsSecurity(.none),
                isCurrent: network.bssid != nil && network.bssid == currentBSSID
            )
        }
        .sorted { $0.rssi > $1.rssi }
    }
}
#endif

// MARK: - Models (cross-platform)

public struct WiFiStatus: Sendable, Hashable, Codable {
    public let ssid: String?
    public let bssid: String?
    public let rssi: Int           // dBm
    public let noise: Int          // dBm
    public let txRateMbps: Double
    public let channel: Int
    public let band: WiFiBand
    public let width: WiFiWidth
    public let phyMode: WiFiPHYMode
    public let interfaceName: String

    public init(ssid: String?, bssid: String?, rssi: Int, noise: Int, txRateMbps: Double,
                channel: Int, band: WiFiBand, width: WiFiWidth, phyMode: WiFiPHYMode, interfaceName: String) {
        self.ssid = ssid; self.bssid = bssid; self.rssi = rssi; self.noise = noise
        self.txRateMbps = txRateMbps; self.channel = channel; self.band = band
        self.width = width; self.phyMode = phyMode; self.interfaceName = interfaceName
    }

    /// Signal-to-noise ratio in dB (higher is better; 40+ is excellent).
    public var snr: Int { rssi - noise }
    public var quality: WiFiQuality { WiFiQuality(rssi: rssi) }
}

public struct WiFiNetwork: Sendable, Hashable, Codable, Identifiable {
    public var id: String { (bssid ?? ssid ?? "?") + "#\(channel)" }
    public let ssid: String?
    public let bssid: String?
    public let rssi: Int
    public let channel: Int
    public let band: WiFiBand
    public let width: WiFiWidth
    public let isSecure: Bool
    public let isCurrent: Bool

    public init(ssid: String?, bssid: String?, rssi: Int, channel: Int, band: WiFiBand,
                width: WiFiWidth, isSecure: Bool, isCurrent: Bool) {
        self.ssid = ssid; self.bssid = bssid; self.rssi = rssi; self.channel = channel
        self.band = band; self.width = width; self.isSecure = isSecure; self.isCurrent = isCurrent
    }

    public var quality: WiFiQuality { WiFiQuality(rssi: rssi) }
}

public enum WiFiBand: String, Sendable, Codable, Hashable {
    case ghz24, ghz5, ghz6, unknown
    public var label: String {
        switch self {
        case .ghz24: "2,4 ГГц"
        case .ghz5: "5 ГГц"
        case .ghz6: "6 ГГц"
        case .unknown: "—"
        }
    }
    #if canImport(CoreWLAN)
    init(_ band: CWChannelBand?) {
        switch band {
        case .some(.band2GHz): self = .ghz24
        case .some(.band5GHz): self = .ghz5
        default:
            if band?.rawValue == 3 { self = .ghz6 } else { self = .unknown }
        }
    }
    #endif
}

public enum WiFiWidth: String, Sendable, Codable, Hashable {
    case mhz20, mhz40, mhz80, mhz160, unknown
    public var label: String {
        switch self {
        case .mhz20: "20 МГц"
        case .mhz40: "40 МГц"
        case .mhz80: "80 МГц"
        case .mhz160: "160 МГц"
        case .unknown: "—"
        }
    }
    #if canImport(CoreWLAN)
    init(_ width: CWChannelWidth?) {
        switch width {
        case .some(.width20MHz): self = .mhz20
        case .some(.width40MHz): self = .mhz40
        case .some(.width80MHz): self = .mhz80
        case .some(.width160MHz): self = .mhz160
        default: self = .unknown
        }
    }
    #endif
}

public enum WiFiPHYMode: String, Sendable, Codable, Hashable {
    case a, b, g, n, ac, ax, none
    /// The marketing "Wi-Fi N" generation name.
    public var label: String {
        switch self {
        case .a: "802.11a"
        case .b: "802.11b"
        case .g: "802.11g"
        case .n: "Wi-Fi 4 (n)"
        case .ac: "Wi-Fi 5 (ac)"
        case .ax: "Wi-Fi 6 (ax)"
        case .none: "—"
        }
    }
    #if canImport(CoreWLAN)
    init(_ mode: CWPHYMode) {
        switch mode {
        case .mode11a: self = .a
        case .mode11b: self = .b
        case .mode11g: self = .g
        case .mode11n: self = .n
        case .mode11ac: self = .ac
        case .mode11ax: self = .ax
        default: self = .none
        }
    }
    #endif
}

/// A coarse signal-quality bucket from RSSI (dBm).
public enum WiFiQuality: String, Sendable, Codable, Hashable {
    case excellent, good, fair, poor

    public init(rssi: Int) {
        switch rssi {
        case (-60)...: self = .excellent   // ≥ −60
        case (-70)..<(-60): self = .good
        case (-80)..<(-70): self = .fair
        default: self = .poor              // < −80
        }
    }

    public var label: String {
        switch self {
        case .excellent: "Отличный"
        case .good: "Хороший"
        case .fair: "Средний"
        case .poor: "Слабый"
        }
    }
    /// Bars 0–3 for an icon.
    public var bars: Int {
        switch self {
        case .excellent: 3
        case .good: 2
        case .fair: 1
        case .poor: 0
        }
    }
}
