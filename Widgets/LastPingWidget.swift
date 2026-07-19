import WidgetKit
import SwiftUI

struct PingEntry: TimelineEntry {
    let date: Date
    let snapshot: PingSnapshot?
}

struct LastPingProvider: TimelineProvider {
    func placeholder(in context: Context) -> PingEntry {
        PingEntry(date: Date(), snapshot: .placeholder)
    }
    func getSnapshot(in context: Context, completion: @escaping (PingEntry) -> Void) {
        completion(PingEntry(date: Date(), snapshot: SharedStore.latestSnapshot() ?? .placeholder))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<PingEntry>) -> Void) {
        let entry = PingEntry(date: Date(), snapshot: SharedStore.latestSnapshot())
        // Refresh periodically; the app also reloads timelines after each run.
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct LastPingWidgetView: View {
    var entry: PingEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let snapshot = entry.snapshot {
            content(snapshot)
        } else {
            emptyState
        }
    }

    private func content(_ s: PingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: StatusStyle.symbol(s.status))
                    .foregroundStyle(StatusStyle.color(s.status))
                Text(s.host).font(.callout.weight(.semibold)).lineLimit(1)
                Spacer()
            }
            Spacer(minLength: 0)
            Text(s.latencyText)
                .font(.system(size: family == .systemSmall ? 30 : 40, weight: .bold, design: .rounded))
                .foregroundStyle(StatusStyle.color(s.status))
            HStack(spacing: 8) {
                Label(s.lossText, systemImage: "arrow.down.circle").font(.caption2)
                if let j = s.jitterMillis {
                    Label("\(Int(j)) мс", systemImage: "waveform.path").font(.caption2)
                }
            }
            .foregroundStyle(.secondary)
            Text(s.timestamp, style: .relative).font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "dot.radiowaves.left.and.right").font(.title).foregroundStyle(.secondary)
            Text("Запустите проверку").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct LastPingWidget: Widget {
    let kind = "LastPingWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LastPingProvider()) { entry in
            LastPingWidgetView(entry: entry)
        }
        .configurationDisplayName("Последняя проверка")
        .description("Задержка и потери до последнего проверенного хоста.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
