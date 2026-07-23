import SwiftUI
import UniformTypeIdentifiers

enum HistoryExporter {
    /// The export formats are machine-readable on purpose, so their column
    /// names and JSON keys stay in English and are **not** localized: an export
    /// has to import into the same spreadsheet or script regardless of the UI
    /// language the user happened to pick.
    enum Format {
        case csv, json

        var filename: String {
            switch self {
            case .csv: "checknet-history.csv"
            case .json: "checknet-history.json"
            }
        }

        var contentType: UTType {
            switch self {
            case .csv: .commaSeparatedText
            case .json: .json
            }
        }
    }

    static func data(_ records: [CheckRecord], format: Format) throws -> Data {
        switch format {
        case .json: try json(records)
        case .csv: try csv(records)
        }
    }

    private static func json(_ records: [CheckRecord]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(records)
    }

    private static func csv(_ records: [CheckRecord]) throws -> Data {
        guard let data = HistoryCSV.document(records).data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return data
    }

    /// A one-line-per-field text summary of a single record, for sharing.
    ///
    /// Unlike the file exports this is prose a person reads, so it follows the
    /// UI language and the caller's locale for the timestamp.
    static func shareText(_ r: CheckRecord, locale: Locale) -> String {
        let time = r.timestamp.formatted(
            Date.FormatStyle(date: .abbreviated, time: .standard).locale(locale)
        )
        let outcome = r.succeeded
            ? String(localized: "успех", locale: locale)
            : String(localized: "проблема", locale: locale)
        var lines = [
            "CheckNet — \(r.tool)",
            String(localized: "Хост: \(r.host)", locale: locale),
            String(localized: "Время: \(time)", locale: locale),
            String(localized: "Результат: \(outcome)", locale: locale)
        ]
        if let latency = r.latencyMillis {
            let value = String(format: "%.1f", latency)
            lines.append(String(localized: "Задержка: \(value) мс", locale: locale))
        }
        if let loss = r.lossPercent {
            let value = String(format: "%.0f", loss)
            lines.append(String(localized: "Потери: \(value)%", locale: locale))
        }
        lines.append(r.detail)
        return lines.joined(separator: "\n")
    }
}

/// A history export handed to the share sheet.
///
/// The bytes are serialized and written to disk inside the transfer
/// representation, which the system calls only once the user has actually
/// picked a share destination. Building the file eagerly instead meant
/// re-encoding up to 2000 records and writing them to disk on every layout
/// pass of the history screen.
/// One representation per type, rather than one type switching on a format:
/// each export declares a single content type, which leaves no room for the
/// wrong representation to be picked.
struct HistoryCSVExport: Transferable {
    let records: [CheckRecord]

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { export in
            SentTransferredFile(try writeExport(export.records, format: .csv))
        }
        .suggestedFileName(HistoryExporter.Format.csv.filename)
    }
}

struct HistoryJSONExport: Transferable {
    let records: [CheckRecord]

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { export in
            SentTransferredFile(try writeExport(export.records, format: .json))
        }
        .suggestedFileName(HistoryExporter.Format.json.filename)
    }
}

private func writeExport(_ records: [CheckRecord], format: HistoryExporter.Format) throws -> URL {
    let data = try HistoryExporter.data(records, format: format)
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(format.filename)
    // No `try?` here: a failed write used to make the share item vanish with
    // no explanation. Thrown, it reaches the share sheet's own error report.
    try data.write(to: url, options: .atomic)
    return url
}

/// Test history. `source` scopes it: manual history is the default; the schedule
/// screen shows its own scheduled history so the two never mix.
struct HistoryView: View {
    var source: HistorySource = .manual
    var title: String = "История"

    /// One day's records, precomputed. Grouping and sorting used to run inside
    /// `body`, i.e. on every render.
    private struct DayGroup: Identifiable {
        let day: Date
        let records: [CheckRecord]
        var id: Date { day }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var records: [CheckRecord] = []
    @State private var groups: [DayGroup] = []
    @State private var expanded: Set<UUID> = []
    @State private var showClearConfirm = false
    @State private var query = ""
    @State private var scope: Scope = .all

    /// History can hold up to 2000 records, so it needs a way in besides
    /// scrolling: by host or tool name, and narrowed to just the failures.
    enum Scope: Hashable { case all, failures }

    var body: some View {
        NavigationStack {
            Group {
                if records.isEmpty {
                    ContentUnavailableView("Нет истории", systemImage: "clock.arrow.circlepath",
                                           description: Text("Результаты проверок будут появляться здесь."))
                } else if groups.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    List {
                        ForEach(groups) { group in
                            Section {
                                ForEach(group.records) { record in
                                    row(record)
                                }
                            } header: {
                                dayTitle(group.day)
                            }
                        }
                    }
                    .refreshable { reload() }
                }
            }
            .searchable(text: $query, prompt: "Хост или инструмент")
            .searchScopes($scope) {
                Text("Все").tag(Scope.all)
                Text("С ошибками").tag(Scope.failures)
            }
            .onChange(of: query) { _, _ in regroup() }
            .onChange(of: scope) { _, _ in regroup() }
            // A plain String would be taken verbatim and never look up a
            // translation, leaving the title Russian in every other language.
            .navigationTitle(LocalizedStringKey(title))
            #if os(iOS)
            .toolbarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        ShareLink("Экспорт CSV",
                                  item: HistoryCSVExport(records: records),
                                  preview: SharePreview("checknet-history.csv"))
                        ShareLink("Экспорт JSON",
                                  item: HistoryJSONExport(records: records),
                                  preview: SharePreview("checknet-history.json"))
                        Divider()
                        Button("Очистить историю", role: .destructive) { showClearConfirm = true }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(records.isEmpty)
                    .accessibilityLabel("Экспорт и очистка истории")
                }
            }
            .confirmationDialog("Очистить всю историю?", isPresented: $showClearConfirm, titleVisibility: .visible) {
                Button("Очистить", role: .destructive) {
                    SharedStore.clearHistory(source: source)
                    records = []
                    groups = []
                }
            }
        }
        .onAppear { reload() }
    }

    private func reload() {
        records = SharedStore.history(source: source)
        regroup()
    }

    private func regroup() {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let filtered = records.filter { record in
            (scope == .all || !record.succeeded) &&
            (trimmed.isEmpty
             || record.host.localizedCaseInsensitiveContains(trimmed)
             || record.tool.localizedCaseInsensitiveContains(trimmed))
        }
        let cal = Calendar.current
        let byDay = Dictionary(grouping: filtered) { cal.startOfDay(for: $0.timestamp) }
        groups = byDay.keys.sorted(by: >).map { day in
            DayGroup(day: day, records: byDay[day]!.sorted { $0.timestamp > $1.timestamp })
        }
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
                        .accessibilityLabel(record.succeeded ? "Успешно" : "С ошибкой")
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
                        .accessibilityHidden(true)
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
            ShareLink(item: HistoryExporter.shareText(record, locale: locale)) {
                Label("Поделиться", systemImage: "square.and.arrow.up")
            }
        }
    }

    private func expandedDetail(_ record: CheckRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent("Инструмент", value: record.tool)
            LabeledContent {
                Text(record.timestamp, format: Date.FormatStyle(date: .abbreviated, time: .standard).locale(locale))
            } label: {
                Text("Время")
            }
            if let loss = record.lossPercent {
                LabeledContent("Потери", value: "\(Int(loss))%")
            }
            ShareLink(item: HistoryExporter.shareText(record, locale: locale)) {
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
        regroup()
    }

    /// Section header for a day. "Сегодня"/"Вчера" go through the string
    /// catalog, and every other date is formatted with the locale the user
    /// selected in Settings rather than a hardcoded `ru_RU`.
    private func dayTitle(_ day: Date) -> Text {
        if Calendar.current.isDateInToday(day) { return Text("Сегодня") }
        if Calendar.current.isDateInYesterday(day) { return Text("Вчера") }
        return Text(day, format: Date.FormatStyle(date: .abbreviated).locale(locale))
    }
}
