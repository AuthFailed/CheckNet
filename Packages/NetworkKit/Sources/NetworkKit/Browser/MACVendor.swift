import Foundation

/// Resolves a MAC address prefix (OUI) to a vendor name using a curated table
/// of common consumer/network vendors. Fully self-contained (no lookup API).
public enum MACVendor {
    public static func lookup(mac: String) -> String? {
        let normalized = mac.uppercased().replacingOccurrences(of: "-", with: ":")
        let parts = normalized.split(separator: ":")
        guard parts.count >= 3 else { return nil }
        let oui = parts.prefix(3).joined(separator: ":")
        return table[oui]
    }

    /// Whether a MAC is locally-administered / randomized (2nd-least-significant
    /// bit of the first octet set) — common for privacy MACs.
    public static func isRandomized(mac: String) -> Bool {
        let parts = mac.split(whereSeparator: { $0 == ":" || $0 == "-" })
        guard let first = parts.first, let byte = UInt8(first, radix: 16) else { return false }
        return (byte & 0x02) != 0
    }

    /// A compact OUI → vendor map of widely-seen prefixes.
    static let table: [String: String] = [
        "00:1A:11": "Google", "3C:5A:B4": "Google", "F4:F5:E8": "Google", "DA:A1:19": "Google",
        "00:03:93": "Apple", "00:0A:27": "Apple", "00:1B:63": "Apple", "00:1E:C2": "Apple",
        "00:25:00": "Apple", "3C:07:54": "Apple", "A4:83:E7": "Apple", "F0:18:98": "Apple",
        "AC:BC:32": "Apple", "D0:81:7A": "Apple", "F8:FF:C2": "Apple", "88:66:5A": "Apple",
        "00:16:CB": "Apple", "B8:E8:56": "Apple", "DC:2B:2A": "Apple", "E0:AC:CB": "Apple",
        "00:00:0C": "Cisco", "00:1B:D4": "Cisco", "00:25:9C": "Cisco", "F4:CF:E2": "Cisco",
        "00:18:0A": "Cisco Meraki", "88:15:44": "Cisco Meraki",
        "00:0C:29": "VMware", "00:50:56": "VMware", "00:1C:14": "VMware",
        "00:15:5D": "Microsoft", "00:17:FA": "Microsoft", "00:50:F2": "Microsoft", "7C:1E:52": "Microsoft",
        "00:1D:D8": "Microsoft", "C8:3F:26": "Microsoft",
        "00:24:E4": "Withings", "00:1A:22": "eQ-3",
        "00:12:17": "Cisco-Linksys", "00:22:6B": "Cisco-Linksys", "48:F8:B3": "Cisco-Linksys",
        "00:14:BF": "Cisco-Linksys", "58:6D:8F": "Cisco-Linksys",
        "00:09:5B": "Netgear", "00:1F:33": "Netgear", "00:26:F2": "Netgear", "20:4E:7F": "Netgear",
        "A0:04:60": "Netgear", "9C:D3:6D": "Netgear", "C4:04:15": "Netgear",
        "00:14:6C": "Netgear", "2C:30:33": "Netgear",
        "00:18:E7": "Cameo/D-Link", "00:1B:11": "D-Link", "00:24:01": "D-Link", "1C:BD:B9": "D-Link",
        "00:05:5D": "D-Link", "14:D6:4D": "D-Link", "78:54:2E": "D-Link",
        "00:0F:B5": "Netgear", "00:1E:2A": "Netgear",
        "00:1D:0F": "TP-Link", "14:CC:20": "TP-Link", "50:C7:BF": "TP-Link", "A4:2B:B0": "TP-Link",
        "EC:08:6B": "TP-Link", "F4:F2:6D": "TP-Link", "AC:84:C6": "TP-Link", "60:32:B1": "TP-Link",
        "00:1C:DF": "Belkin", "94:10:3E": "Belkin", "08:86:3B": "Belkin",
        "00:24:B2": "Netgear", "44:94:FC": "Netgear",
        "00:90:A9": "Western Digital", "00:14:EE": "Western Digital",
        "00:11:32": "Synology", "00:1B:2F": "Synology", "24:5E:BE": "QNAP", "00:08:9B": "QNAP",
        "FC:EC:DA": "Ubiquiti", "24:A4:3C": "Ubiquiti", "44:D9:E7": "Ubiquiti", "78:8A:20": "Ubiquiti",
        "68:D7:9A": "Ubiquiti", "B4:FB:E4": "Ubiquiti", "E0:63:DA": "Ubiquiti", "74:83:C2": "Ubiquiti",
        "00:1D:AA": "MikroTik", "48:8F:5A": "MikroTik", "64:D1:54": "MikroTik", "6C:3B:6B": "MikroTik",
        "CC:2D:E0": "MikroTik", "DC:2C:6E": "MikroTik", "E4:8D:8C": "MikroTik",
        "00:17:88": "Philips Hue",
        "18:B4:30": "Nest", "64:16:66": "Nest",
        "44:65:0D": "Amazon", "68:37:E9": "Amazon", "FC:65:DE": "Amazon", "F0:27:2D": "Amazon",
        "00:BB:3A": "Amazon", "50:DC:E7": "Amazon", "AC:63:BE": "Amazon", "68:54:FD": "Amazon",
        "00:12:FB": "Samsung", "00:15:99": "Samsung", "5C:0A:5B": "Samsung", "78:1F:DB": "Samsung",
        "8C:77:12": "Samsung", "E8:50:8B": "Samsung", "F0:25:B7": "Samsung", "34:23:BA": "Samsung",
        "00:24:54": "Sony", "00:1D:BA": "Sony", "FC:0F:E6": "Sony", "54:42:49": "Sony",
        "00:09:B0": "Onkyo", "00:04:20": "Slim Devices/Logitech",
        "B8:27:EB": "Raspberry Pi", "DC:A6:32": "Raspberry Pi", "E4:5F:01": "Raspberry Pi",
        "28:CD:C1": "Raspberry Pi", "D8:3A:DD": "Raspberry Pi",
        "00:1E:06": "WIBRAIN", "18:FE:34": "Espressif (ESP)", "24:0A:C4": "Espressif (ESP)",
        "30:AE:A4": "Espressif (ESP)", "3C:71:BF": "Espressif (ESP)", "84:0D:8E": "Espressif (ESP)",
        "5C:CF:7F": "Espressif (ESP)", "A4:CF:12": "Espressif (ESP)", "24:6F:28": "Espressif (ESP)",
        "00:0E:8F": "Sercomm", "00:26:B8": "ActionTec",
        "00:1F:3F": "AVM (Fritz!Box)", "00:04:0E": "AVM (Fritz!Box)", "3C:A6:2F": "AVM (Fritz!Box)",
        "38:10:D5": "AVM (Fritz!Box)", "C0:25:06": "AVM (Fritz!Box)",
        "00:1C:B3": "Apple", "70:56:81": "Apple", "9C:20:7B": "Apple", "F0:99:BF": "Apple",
        "00:04:F2": "Polycom", "64:16:7F": "Polycom",
        "00:1E:8C": "ASUSTek", "00:22:15": "ASUSTek", "AC:9E:17": "ASUSTek", "2C:56:DC": "ASUSTek",
        "50:46:5D": "ASUSTek", "1C:87:2C": "ASUSTek", "04:D4:C4": "ASUSTek",
        "00:E0:4C": "Realtek", "52:54:00": "QEMU/KVM"
    ]
}
