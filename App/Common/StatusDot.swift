import SwiftUI

/// A status marker that survives being seen in greyscale and being read aloud.
///
/// The screens used to mark status with a plain coloured `Circle()`: green for
/// reachable, red for down. That carries the whole meaning in hue, which is
/// exactly the channel a red-green colour-blind user does not have and
/// VoiceOver never sees at all. Here the shape differs per level as well, and
/// the marker states its meaning in words.
struct StatusDot: View {
    enum Level {
        case ok, warning, bad, unknown

        var symbol: String {
            switch self {
            case .ok: "checkmark.circle.fill"
            case .warning: "exclamationmark.triangle.fill"
            case .bad: "xmark.octagon.fill"
            case .unknown: "questionmark.circle"
            }
        }

        var tint: Color {
            switch self {
            case .ok: .green
            case .warning: .orange
            case .bad: .red
            case .unknown: .gray
            }
        }
    }

    let level: Level
    /// What this marker means here — "порт открыт", "хост отвечает". Read by
    /// VoiceOver in place of the shape.
    let label: LocalizedStringKey
    /// Matches the marker to the text beside it instead of a fixed 8 pt.
    @ScaledMetric(relativeTo: .caption) private var size: CGFloat = 11

    var body: some View {
        Image(systemName: level.symbol)
            .font(.system(size: size))
            .foregroundStyle(level.tint)
            .accessibilityLabel(label)
    }
}

extension StatusDot.Level {
    /// Bridges the shared ping status used by monitoring, history and the
    /// widget.
    init(_ status: PingSnapshot.Status) {
        switch status {
        case .ok: self = .ok
        case .degraded: self = .warning
        case .down: self = .bad
        case .unknown: self = .unknown
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        StatusDot(level: .ok, label: "Хост отвечает")
        StatusDot(level: .warning, label: "Есть потери")
        StatusDot(level: .bad, label: "Хост недоступен")
        StatusDot(level: .unknown, label: "Нет данных")
    }
    .padding()
}
