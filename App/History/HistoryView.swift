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

    /// A one-line-per-field text summary of a single record, for sharing.
    static func shareText(_ r: CheckRecord) -> String {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .medium
        var lines = [
            "CheckNet — \(r.tool)",
            "Хост: \(r.host)",
            "Время: \(f.string(from: r.timestamp))",
            "Результат: \(r.succeeded ? "успех" : "проблема")"
        ]
        if let latency = r.latencyMillis { lines.append("Задержка: \(String(format: "%.1f", latency)) мс") }
        if let loss = r.lossPercent { lines.append("Потери: \(String(format: "%.0f", loss))%") }
        lines.append(r.detail)
        return lines.joined(separator: "\n")
    }

    private static func write(_ data: Data, filename: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? data.write(to: url, options: .atomic)
        return url
    }
}

/// Test history. `source` scopes it: manual history is the default; the schedule
/// screen shows its own scheduled history so the two never mix.
struct HistoryView: View {
    var source: HistorySource = .manual
    var title: String = "История"

    @Environment(\.dismiss) private var dismiss
    @State private var records: [CheckRecord] = []
    @State private var expanded: Set<UUID> = []
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
            .navigationTitle(title)
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
                    SharedStore.clearHistory(source: source)
                    records = []
                }
            }
        }
        .onAppear { records = SharedStore.history(source: source) }
    }

    private func row(_ record: CheckRecord) -> some View {
        let isOpen = expanded.contains(record.id)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                toggle(record.id)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: record.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(record.succeeded ? .green : .red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.host).font(.callout.weight(.medium))
                        Text(record.detail).font(.caption).foregroundStyle(.secondary)
                            .lineLimit(isOpen ? nil : 1)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        if let latency = record.latencyMillis {
                            Text("\(Int(latency)) мс").font(.callout.monospaced())
                        }
                        Text(record.timestamp, style: .time).font(.caption2).foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                }
            }
            .buttonStyle(.plain)

            if isOpen {
                expandedDetail(record)
            }
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                delete(record)
            } label: { Label("Удалить", systemImage: "trash") }
            ShareLink(item: HistoryExporter.shareText(record)) {
                Label("Поделиться", systemImage: "square.and.arrow.up")
            }
        }
    }

    private func expandedDetail(_ record: CheckRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent("Инструмент", value: record.tool)
            LabeledContent("Время", value: record.timestamp.formatted(date: .abbreviated, time: .standard))
            if let loss = record.lossPercent {
                LabeledContent("Потери", value: "\(Int(loss))%")
            }
            ShareLink(item: HistoryExporter.shareText(record)) {
                Label("Поделиться результатом", systemImage: "square.and.arrow.up")
            }
            .font(.callout)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.top, 8)
        .padding(.leading, 28)
    }

    private func toggle(_ id: UUID) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }

    private func delete(_ record: CheckRecord) {
        SharedStore.deleteHistory(id: record.id)
        records.removeAll { $0.id == record.id }
        expanded.remove(record.id)
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
