import SwiftUI
import UniformTypeIdentifiers
import NetworkKit

@MainActor
@Observable
final class MRSViewModel {
    private(set) var ruleSet: MRSRuleSet?
    private(set) var sourceName: String?
    private(set) var isLoading = false
    var error: String?
    var urlText = ""

    func openFile(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            load(data, name: url.lastPathComponent)
        } catch {
            self.error = "Не удалось открыть файл: \(error.localizedDescription)"
        }
    }

    func loadFromURL() {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme?.hasPrefix("http") == true else {
            error = "Некорректная ссылка"; return
        }
        isLoading = true; error = nil
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                await parse(data, name: url.lastPathComponent + " · загружен")
            } catch {
                self.error = "Не удалось загрузить: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }

    func load(_ data: Data, name: String) {
        isLoading = true; error = nil
        Task { await parse(data, name: name) }
    }

    private func parse(_ data: Data, name: String) async {
        // Decompress + trie enumeration off the main thread.
        let outcome = await Task.detached {
            Result { try MRSParser.parse(data) }
        }.value
        switch outcome {
        case .success(let set):
            ruleSet = set; sourceName = name; error = nil
        case .failure(let e):
            error = Self.friendly(e)
        }
        isLoading = false
    }

    private static func friendly(_ error: Error) -> String {
        switch error as? MRSParser.ParseError {
        case .notCompressed: "Это не .mrs файл (не zstd)."
        case .badMagic: "Не похоже на mihomo rule-set (нет метки MRS)."
        case .badVersion: "Неподдерживаемая версия формата."
        case .unsupportedBehavior(let b): "Неизвестный тип rule-set (\(b)). Поддерживаются domain и ipcidr."
        case .truncated, .none: "Файл повреждён или обрезан."
        }
    }
}

/// Просмотр mihomo rule-set (#74): распаковывает `.mrs` (zstd + succinct-trie /
/// ipcidr) обратно в список доменов или подсетей с поиском и экспортом. Чистая
/// диагностика — разбор ваших списков на устройстве, без маршрутизации трафика.
struct MRSView: View {
    @State private var model = MRSViewModel()
    @State private var showImporter = false
    @State private var search = ""

    private var items: [String] {
        guard let set = model.ruleSet else { return [] }
        return set.behavior == .domain ? set.domains : set.cidrs
    }

    private var filtered: [String] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return items }
        return items.filter { $0.lowercased().contains(q) }
    }

    var body: some View {
        Group {
            if let set = model.ruleSet {
                loaded(set)
            } else {
                idle
            }
        }
        .navigationTitle("Правила mihomo (.mrs)")
        .toolTitleDisplayMode()
        .toolbar {
            if model.ruleSet != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button { showImporter = true } label: {
                        Label("Открыть файл", systemImage: "folder")
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    ShareLink(item: items.joined(separator: "\n")) {
                        Label("Экспорт списка", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.data, .item]) { result in
            if case .success(let url) = result { model.openFile(url) }
            if case .failure(let e) = result { model.error = e.localizedDescription }
        }
    }

    // MARK: - Idle

    private var idle: some View {
        List {
            Section {
                Button { showImporter = true } label: {
                    Label("Открыть .mrs файл", systemImage: "folder")
                }
            } footer: {
                Text("Скомпилированный rule-set mihomo (`.mrs`) — это zstd-сжатый список доменов или подсетей. Откройте свой файл или загрузите его по ссылке ниже; тип (домены/подсети) определяется автоматически.")
            }

            Section("Загрузить по ссылке") {
                HStack {
                    Image(systemName: "link").foregroundStyle(.secondary)
                    TextField("https://…/ruleset.mrs", text: $model.urlText)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        #endif
                        .onSubmit { model.loadFromURL() }
                }
                Button("Загрузить") { model.loadFromURL() }
                    .disabled(model.urlText.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if model.isLoading {
                HStack { ProgressView(); Text("Распаковка…").foregroundStyle(.secondary) }
            }
            if let error = model.error {
                Text(LocalizedStringKey(error)).foregroundStyle(.red).font(.callout)
            }
        }
    }

    // MARK: - Loaded

    private func loaded(_ set: MRSRuleSet) -> some View {
        List {
            Section {
                HStack {
                    Label(set.behavior == .domain ? "Домены" : "Подсети",
                          systemImage: set.behavior == .domain ? "globe" : "network")
                    Spacer()
                    Text("\(set.itemCount) правил").font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if set.entryCount != set.itemCount {
                    Text("Исходных записей: \(set.entryCount) (после слияния — \(set.itemCount))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if let name = model.sourceName {
                    Text(name).font(.caption2).foregroundStyle(.secondary)
                }
            }

            Section(set.behavior == .domain ? "Домены" : "Подсети") {
                if filtered.isEmpty {
                    Text("Ничего не найдено").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(filtered, id: \.self) { item in
                        Text(item)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .searchable(text: $search, prompt: set.behavior == .domain ? "Домен" : "Подсеть")
    }
}
