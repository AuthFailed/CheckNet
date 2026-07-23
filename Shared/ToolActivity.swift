import Foundation

/// Handoff / continuation payload describing which tool (and host) is open, so
/// the same screen can resume on another device.
///
/// Pure and shared so the advertiser (the tool screen) and the receiver (the
/// app's continuation handler) agree on the keys, and the codec is unit-tested
/// rather than eyeballed across two devices.
enum ToolActivity {
    /// Also listed in the app's Info.plist `NSUserActivityTypes` — the system
    /// only hands back activities of a declared type.
    static let type = "com.chrsnv.checknet.tool"

    private static let toolKey = "tool"
    private static let hostKey = "host"

    struct Payload: Equatable {
        var toolRawValue: String
        var host: String?
    }

    static func userInfo(toolRawValue: String, host: String?) -> [String: String] {
        var info = [toolKey: toolRawValue]
        if let host, !host.trimmingCharacters(in: .whitespaces).isEmpty { info[hostKey] = host }
        return info
    }

    static func payload(from userInfo: [AnyHashable: Any]?) -> Payload? {
        guard let raw = userInfo?[toolKey] as? String, !raw.isEmpty else { return nil }
        let host = userInfo?[hostKey] as? String
        return Payload(toolRawValue: raw, host: (host?.isEmpty ?? true) ? nil : host)
    }
}

/// Merges two saved-host lists into one. Used by QR import today and by iCloud
/// sync when it is enabled. Union by address (scoped separately per tool); the
/// first list's entry wins on a clash, so a local name is never overwritten by
/// a remote one. Pure so the merge is deterministic and unit-tested.
enum SavedHostMerge {
    static func union(_ primary: [SavedHost], _ secondary: [SavedHost]) -> [SavedHost] {
        var seen = Set<String>()
        var out: [SavedHost] = []
        for host in primary + secondary {
            let value = host.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            // Global and tool-scoped entries with the same address are distinct.
            let key = value.lowercased() + "\u{1}" + (host.toolID ?? "")
            guard seen.insert(key).inserted else { continue }
            out.append(host)
        }
        return out
    }
}
