import SwiftUI
import UniformTypeIdentifiers
import NetworkKit

@MainActor
@Observable
final class GeoDataModel {
    private(set) var document: GeoDataDocument?
    private(set) var isLoading = false
    var error: String?
    private(set) var sourceName: String?

    var lookupQuery = ""
    private(set) var lookupResults: [String]?
    private(set) var lookingUp = false

    func openFile(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            load(data, name: url.lastPathComponent, kind: nil)
        } catch {
            self.error = "Couldn't open file: \(error.localizedDescription)"
        }
    }

    func download(_ kind: GeoDataKind) async {
        let name = kind == .geosite ? "geosite.dat" : "geoip.dat"
        let url = URL(string: "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/\(name)")!
        isLoading = true; error = nil
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            await parse(data, name: "\(name) · downloaded", kind: kind)
        } catch {
            self.error = "Couldn't download: \(error.localizedDescription)"
            isLoading = false
        }
    }

    func load(_ data: Data, name: String, kind: GeoDataKind?) {
        isLoading = true; error = nil
        Task { await parse(data, name: name, kind: kind) }
    }

    private func parse(_ data: Data, name: String, kind: GeoDataKind?) async {
        let doc = await Task.detached { GeoDataDocument.load(data, kind: kind) }.value
        if let doc {
            document = doc; sourceName = name
            lookupResults = nil; lookupQuery = ""
        } else {
            error = "Couldn't parse the file — is it not geosite.dat / geoip.dat?"
        }
        isLoading = false
    }

    func runLookup() {
        guard let doc = document else { return }
        let q = lookupQuery.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { lookupResults = nil; return }
        lookingUp = true; lookupResults = nil
        Task {
            let results = await Task.detached {
                doc.kind == .geosite ? doc.categoriesContaining(domain: q) : doc.categoriesContaining(ip: q)
            }.value
            lookupResults = results
            lookingUp = false
        }
    }
}

/// Viewer for geosite/geoip `.dat` (#73): open a file (or download the standard one),
/// see the categories and their rules, search for a domain/IP across categories. Pure
/// diagnostics — parsing your own lists on the device.
struct GeoDataView: View {
    @State private var model = GeoDataModel()
    @State private var showImporter = false
    @State private var categorySearch = ""

    private var filteredCategories: [GeoCategory] {
        guard let cats = model.document?.categories else { return [] }
        let q = categorySearch.trimmingCharacters(in: .whitespaces).uppercased()
        guard !q.isEmpty else { return cats }
        return cats.filter { $0.code.contains(q) }
    }

    var body: some View {
        Group {
            if let doc = model.document {
                loaded(doc)
            } else {
                idle
            }
        }
        .navigationTitle("geosite / geoip")
        .toolTitleDisplayMode()
        .toolbar {
            if model.document != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button { showImporter = true } label: {
                        Label("Open file", systemImage: "folder")
                    }
                }
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.data, .item]) { result in
            if case .success(let url) = result { model.openFile(url) }
            if case .failure(let e) = result { model.error = e.localizedDescription }
        }
    }

    // MARK: - Idle (no file)

    private var idle: some View {
        List {
            Section {
                Button { showImporter = true } label: {
                    Label("Open .dat file", systemImage: "folder")
                }
                Button { Task { await model.download(.geosite) } } label: {
                    Label("Load default geosite.dat", systemImage: "arrow.down.circle")
                }
                Button { Task { await model.download(.geoip) } } label: {
                    Label("Load default geoip.dat", systemImage: "arrow.down.circle")
                }
            } footer: {
                Text("Open your own geosite.dat / geoip.dat or load a Loyalsoldier build. The type is detected automatically.")
            }
            if model.isLoading {
                HStack { ProgressView(); Text("Loading…").foregroundStyle(.secondary) }
            }
            if let error = model.error {
                Text(LocalizedStringKey(error)).foregroundStyle(.red).font(.callout)
            }
        }
    }

    // MARK: - Loaded

    private func loaded(_ doc: GeoDataDocument) -> some View {
        List {
            Section {
                HStack {
                    Label(doc.kind == .geosite ? "geosite" : "geoip",
                          systemImage: doc.kind == .geosite ? "globe" : "network")
                    Spacer()
                    Text("\(doc.categories.count) cat. · \(doc.totalRules) rules")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                if let name = model.sourceName {
                    Text(name).font(.caption2).foregroundStyle(.secondary)
                }
            }

            Section {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(doc.kind == .geosite ? "Domain: which categories?" : "IPv4: which category?",
                              text: $model.lookupQuery)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .onSubmit { model.runLookup() }
                    if model.lookingUp { ProgressView() }
                }
                if let results = model.lookupResults {
                    if results.isEmpty {
                        Text("Not found in any category").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text(results.joined(separator: ", "))
                            .font(.callout).textSelection(.enabled)
                    }
                }
            } header: {
                Text("Search by category")
            }

            Section("Categories") {
                ForEach(filteredCategories) { cat in
                    NavigationLink {
                        GeoCategoryDetailView(document: doc, category: cat)
                    } label: {
                        HStack {
                            Text(cat.code)
                            Spacer()
                            Text("\(cat.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .searchable(text: $categorySearch, prompt: "Category")
    }
}

/// Rules inside one category, searchable.
struct GeoCategoryDetailView: View {
    let document: GeoDataDocument
    let category: GeoCategory
    @State private var search = ""
    @State private var domains: [GeoDomain] = []
    @State private var cidrs: [GeoCIDR] = []

    private var filteredDomains: [GeoDomain] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return domains }
        return domains.filter { $0.value.lowercased().contains(q) }
    }
    private var filteredCIDRs: [GeoCIDR] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return cidrs }
        return cidrs.filter { $0.text.contains(q) }
    }

    var body: some View {
        List {
            if document.kind == .geosite {
                ForEach(filteredDomains) { domain in
                    HStack(spacing: 10) {
                        Text(domain.kind.label)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(color(domain.kind))
                            .frame(width: 62, alignment: .leading)
                        Text(domain.value)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                        if !domain.attributes.isEmpty {
                            Spacer(minLength: 4)
                            Text(domain.attributes.map { "@\($0)" }.joined(separator: " "))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                ForEach(filteredCIDRs) { cidr in
                    Text(cidr.text)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
        .searchable(text: $search, prompt: document.kind == .geosite ? "Domain" : "Subnet")
        .navigationTitle(category.code)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            if document.kind == .geosite { domains = document.domains(in: category) }
            else { cidrs = document.cidrs(in: category) }
        }
    }

    private func color(_ kind: GeoDomain.Kind) -> Color {
        switch kind {
        case .full: .green
        case .domain: .blue
        case .plain: .orange
        case .regex: .purple
        }
    }
}
