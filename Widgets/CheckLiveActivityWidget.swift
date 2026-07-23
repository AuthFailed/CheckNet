import WidgetKit
import SwiftUI
import ActivityKit
import AppIntents

/// Live Activity presentation for any check (`CheckActivityAttributes`): Lock
/// Screen banner + Dynamic Island in every form. The content is tool-agnostic —
/// a status, a big headline, a caption and up to three stat chips — so ping,
/// monitoring and future tools share one surface. `kind` only picks the icon
/// and whether the interactive "Стоп" button appears.
struct CheckLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CheckActivityAttributes.self) { context in
            lockScreen(context)
                .activityBackgroundTint(Color.black.opacity(0.35))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(context.attributes.title).font(.caption).lineLimit(1)
                    } icon: {
                        Image(systemName: icon(context))
                            .foregroundStyle(StatusStyle.color(context.state.status))
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.headline)
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(StatusStyle.color(context.state.status))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        HStack {
                            ForEach(Array(context.state.stats.enumerated()), id: \.offset) { index, s in
                                if index > 0 { Spacer() }
                                stat(s.label, s.value)
                            }
                        }
                        if showsStop(context) { stopButton(fill: true) }
                    }
                    .padding(.top, 2)
                }
            } compactLeading: {
                Image(systemName: icon(context))
                    .foregroundStyle(StatusStyle.color(context.state.status))
            } compactTrailing: {
                Text(context.state.headline)
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(StatusStyle.color(context.state.status))
            } minimal: {
                Image(systemName: StatusStyle.symbol(context.state.status))
                    .foregroundStyle(StatusStyle.color(context.state.status))
            }
        }
    }

    private func lockScreen(_ context: ActivityViewContext<CheckActivityAttributes>) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(StatusStyle.color(context.state.status).opacity(0.3), lineWidth: 4)
                    Image(systemName: icon(context))
                        .font(.title2)
                        .foregroundStyle(StatusStyle.color(context.state.status))
                }
                .frame(width: 46, height: 46)

                VStack(alignment: .leading, spacing: 3) {
                    Text(context.attributes.title).font(.headline).lineLimit(1)
                    Text("\(context.attributes.subtitle) · \(context.state.caption)")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Text(context.state.headline)
                    .font(.title2.weight(.bold).monospacedDigit())
                    .foregroundStyle(StatusStyle.color(context.state.status))
            }
            if showsStop(context) { stopButton(fill: true) }
        }
        .padding()
    }

    // MARK: Pieces

    private func icon(_ context: ActivityViewContext<CheckActivityAttributes>) -> String {
        switch context.attributes.kind {
        case .ping: return "dot.radiowaves.left.and.right"
        case .monitor: return "bell.badge"
        case .speed: return "speedometer"
        case .bufferbloat: return "waveform.path.ecg"
        case .mtr: return "chart.line.uptrend.xyaxis"
        case .traceroute: return "point.3.connected.trianglepath.dotted"
        case .portScan: return "square.grid.3x3.middle.filled"
        case .ipScan: return "barcode.viewfinder"
        case .lookup: return "magnifyingglass"
        case .worldPing: return "globe"
        case .mtu: return "ruler"
        case .bonjour: return "bonjour"
        case .browser: return "network"
        }
    }

    /// Only ping runs are user-stoppable from the activity; monitoring is
    /// managed in the app.
    private func showsStop(_ context: ActivityViewContext<CheckActivityAttributes>) -> Bool {
        context.attributes.kind == .ping && context.state.isRunning
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.caption.weight(.semibold).monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    /// Interactive "Стоп" — a `LiveActivityIntent` runs in the app and ends the
    /// ping.
    private func stopButton(fill: Bool) -> some View {
        Button(intent: StopPingLiveActivityIntent()) {
            Label("Стоп", systemImage: "stop.fill")
                .font(.caption.weight(.semibold))
                .frame(maxWidth: fill ? .infinity : nil)
        }
        .tint(.red)
        .buttonStyle(.bordered)
    }
}
