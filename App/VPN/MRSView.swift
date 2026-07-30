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
            self.error = "Couldn't open file: \(error.localizedDescription)"
        }
    }

    func loadFromURL() {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme?.hasPrefix("http") == true else {
            error = "Invalid link"; return
        }
        isLoading = true; error = nil
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                await parse(data, name: url.lastPathComponent + " · loaded")
            } catch {
                self.error = "Couldn't download: \(error.localizedDescription)"
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
        case .notCompressed: "Not a .mrs file (not zstd)."
        case .badMagic: "Doesn't look like a mihomo rule-set (no MRS marker)."
        case .badVersion: "Unsupported format version."
        case .unsupportedBehavior(let b): "Unknown rule-set type (\(b)). Only domain and ipcidr are supported."
        case .truncated, .none: "The file is corrupted or truncated."
        }
    }
}

/// Viewer for mihomo rule-set (#74): unpacks `.mrs` (zstd + succinct-trie /
/// ipcidr) back into a list of domains or subnets with search and export. Pure
/// diagnostics — parsing your own lists on the device, without routing traffic.
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
        .navigationTitle("mihomo rules (.mrs)")
        .toolTitleDisplayMode()
        .toolbar {
            if model.ruleSet != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button { showImporter = true } label: {
                        Label("Open file", systemImage: "folder")
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    ShareLink(item: items.joined(separator: "\n")) {
                        Label("Export list", systemImage: "square.and.arrow.up")
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
                    Label("Open .mrs file", systemImage: "folder")
                }
            } footer: {
                Text("A compiled mihomo rule-set (`.mrs`) is a zstd-compressed list of domains or subnets. Open your own file or load it from the link below; the type (domains/subnets) is detected automatically.")
            }

            Section("Load from link") {
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
                Button("Load") { model.loadFromURL() }
                    .disabled(model.urlText.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if model.isLoading {
                HStack { ProgressView(); Text("Unpacking…").foregroundStyle(.secondary) }
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
                    Label(set.behavior == .domain ? "Domains" : "Subnets",
                          systemImage: set.behavior == .domain ? "globe" : "network")
                    Spacer()
                    Text("\(set.itemCount) rules").font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if set.entryCount != set.itemCount {
                    Text("Source records: \(set.entryCount) (after merge — \(set.itemCount))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if let name = model.sourceName {
                    Text(name).font(.caption2).foregroundStyle(.secondary)
                }
            }

            Section(set.behavior == .domain ? "Domains" : "Subnets") {
                if filtered.isEmpty {
                    Text("Nothing found").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(filtered, id: \.self) { item in
                        Text(item)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .searchable(text: $search, prompt: set.behavior == .domain ? "Domain" : "Subnet")
    }
}
