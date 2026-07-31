import SwiftUI

/// UI helpers shared by the widgets and the Live Activity.
enum StatusStyle {
    static func color(_ status: PingSnapshot.Status) -> Color {
        switch status {
        case .ok: return .green
        case .degraded: return .orange
        case .down: return .red
        case .unknown: return .gray
        }
    }
    /// What the marker means in words — for VoiceOver, and for anyone reading
    /// the screen in greyscale.
    static func label(_ status: PingSnapshot.Status) -> String {
        switch status {
        case .ok: return "Responds"
        case .degraded: return "Packet loss"
        case .down: return "Unreachable"
        case .unknown: return "No data"
        }
    }
    static func symbol(_ status: PingSnapshot.Status) -> String {
        switch status {
        case .ok: return "checkmark.circle.fill"
        case .degraded: return "exclamationmark.triangle.fill"
        case .down: return "xmark.octagon.fill"
        case .unknown: return "questionmark.circle"
        }
    }
}

extension PingSnapshot {
    var latencyText: String {
        guard let latencyMillis else { return "—" }
        return "\(Int(latencyMillis)) ms"
    }
    var lossText: String { "\(Int(lossPercent))%" }
}
