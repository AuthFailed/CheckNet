import SwiftUI

enum HistoryExporter {
    static func json(_ records: [CheckRecord]) -> URL? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(records) else { return nil }
        return write(data, filename: "checknet-history.json")
    }

    static func csv(_ records: [CheckRecord]) -> URL? {
        var lines = ["timestamp,tool,host,latency_ms,loss_pct,succeeded,detail"]
        let formatter = ISO8601DateFormatter()
        for r in records {
            let latency = r.latencyMillis.map { String(format: "%.1f", $0) } ?? ""
            let loss = r.lossPercent.map { String(format: "%.1f", $0) } ?? ""
            let detail = "\"\(r.detail.replacingOccurrences(of: "\"", with: "\"\""))\""
            lines.append("\(formatter.string(from: r.timestamp)),\(r.tool),\(r.host),\(latency),\(loss),\(r.succeeded),\(detail)")
        }
        guard let data = lines.joined(separator: "\n").data(using: .utf8) else { return nil }
        return write(data, filename: "checknet-history.csv")
    }

    private static func write(_ data: Data, filename: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? data.write(to: url, options: .atomic)
        return url
    }
}

struct HistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var records: [CheckRecord] = []
    @State private var showClearConfirm = false

    private var grouped: [(day: Date, records: [CheckRecord])] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: records) { cal.startOfDay(for: $0.timestamp) }
        return groups.keys.sorted(by: >).map { ($0, groups[$0]!.sorted { $0.timestamp > $1.timestamp }) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if records.isEmpty {
                    ContentUnavailableView("Нет истории", systemImage: "clock.arrow.circlepath",
                                           description: Text("Результаты проверок будут появляться здесь."))
                } else {
                    List {
                        ForEach(grouped, id: \.day) { group in
                            Section(dayTitle(group.day)) {
                                ForEach(group.records) { record in
                                    row(record)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("История")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        if let url = HistoryExporter.csv(records) {
                            ShareLink("Экспорт CSV", item: url)
                        }
                        if let url = HistoryExporter.json(records) {
                            ShareLink("Экспорт JSON", item: url)
                        }
                        Divider()
                        Button("Очистить историю", role: .destructive) { showClearConfirm = true }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(records.isEmpty)
                }
            }
            .confirmationDialog("Очистить всю историю?", isPresented: $showClearConfirm, titleVisibility: .visible) {
                Button("Очистить", role: .destructive) {
                    SharedStore.clearHistory(); records = []
                }
            }
        }
        .onAppear { records = SharedStore.history() }
    }

    private func row(_ record: CheckRecord) -> some View {
        HStack(spacing: 12) {
            Image(systemName: record.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(record.succeeded ? .green : .red)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.host).font(.callout.weight(.medium))
                Text(record.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let latency = record.latencyMillis {
                    Text("\(Int(latency)) мс").font(.callout.monospaced())
                }
                Text(record.timestamp, style: .time).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func dayTitle(_ day: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        if Calendar.current.isDateInToday(day) { return "Сегодня" }
        if Calendar.current.isDateInYesterday(day) { return "Вчера" }
        f.dateStyle = .medium
        return f.string(from: day)
    }
}
