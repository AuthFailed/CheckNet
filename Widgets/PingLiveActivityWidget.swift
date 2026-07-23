import WidgetKit
import SwiftUI
import ActivityKit

/// Live Activity presentation: Lock Screen banner + Dynamic Island in all forms.
struct PingLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PingActivityAttributes.self) { context in
            lockScreen(context)
                .activityBackgroundTint(Color.black.opacity(0.35))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(context.attributes.host).font(.caption).lineLimit(1)
                    } icon: {
                        Image(systemName: StatusStyle.symbol(context.state.status))
                            .foregroundStyle(StatusStyle.color(context.state.status))
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(latency(context.state))
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(StatusStyle.color(context.state.status))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        stat("Потери", "\(Int(context.state.lossPercent))%")
                        Spacer()
                        stat("Пакеты", "\(context.state.received)/\(context.state.transmitted)")
                        Spacer()
                        stat("Статус", statusText(context.state))
                    }
                    .padding(.top, 2)
                }
            } compactLeading: {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .foregroundStyle(StatusStyle.color(context.state.status))
            } compactTrailing: {
                Text(latency(context.state))
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(StatusStyle.color(context.state.status))
            } minimal: {
                Image(systemName: StatusStyle.symbol(context.state.status))
                    .foregroundStyle(StatusStyle.color(context.state.status))
            }
        }
    }

    private func lockScreen(_ context: ActivityViewContext<PingActivityAttributes>) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(StatusStyle.color(context.state.status).opacity(0.3), lineWidth: 4)
                Image(systemName: StatusStyle.symbol(context.state.status))
                    .font(.title2)
                    .foregroundStyle(StatusStyle.color(context.state.status))
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 3) {
                Text(context.attributes.host).font(.headline).lineLimit(1)
                Text("\(context.attributes.ip) · \(context.state.isRunning ? "идёт проверка" : "завершено")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(latency(context.state))
                    .font(.title2.weight(.bold).monospacedDigit())
                    .foregroundStyle(StatusStyle.color(context.state.status))
                Text("потери \(Int(context.state.lossPercent))%")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.caption.weight(.semibold).monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func latency(_ state: PingActivityAttributes.ContentState) -> String {
        guard let l = state.latencyMillis else { return "—" }
        return "\(Int(l)) мс"
    }

    private func statusText(_ state: PingActivityAttributes.ContentState) -> String {
        switch state.status {
        case .ok: return "OK"
        case .degraded: return "Плохо"
        case .down: return "Нет"
        case .unknown: return "…"
        }
    }
}
