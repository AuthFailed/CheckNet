import SwiftUI
import NetworkKit

/// Manages Xray cores for the "through proxy" check.
///
/// On macOS: download a chosen version with progress, keep several versions,
/// delete one or all. On iOS a core cannot be downloaded/run
/// (App Store 2.5.2), so we show the latest available version and explain that
/// the through-proxy check there uses the native Reality probe.
struct XrayCoresEditor: View {
    @Environment(XrayCoreStore.self) private var store
    @State private var confirmDeleteAll = false

    var body: some View {
        List {
            if !XrayCoreStore.isSupported {
                Section {
                    Label("Xray core is available on Mac", systemImage: "desktopcomputer")
                        .font(.headline)
                    Text("iOS doesn't allow downloading and running a third-party core. The \"via proxy\" check on iPhone uses a built-in Reality probe without loading a core.")
                        .font(.callout).foregroundStyle(.secondary)
                    if let latest = store.latestVersion {
                        InfoRow(label: "Latest Xray version", value: latest, mono: true)
                    }
                } footer: {
                    Text("On Mac you can download and keep multiple core versions here.")
                }
            }

            if !store.installed.isEmpty {
                Section("Installed") {
                    ForEach(store.installed) { core in
                        HStack {
                            Label(core.version, systemImage: "shippingbox")
                            Spacer()
                            Text("\(core.sizeMB, specifier: "%.1f") MB").foregroundStyle(.secondary).font(.caption)
                        }
                    }
                    .onDelete { idx in idx.map { store.installed[$0].version }.forEach(store.remove) }

                    Button(role: .destructive) { confirmDeleteAll = true } label: {
                        Label("Delete all cores", systemImage: "trash")
                    }
                }
            }

            if XrayCoreStore.isSupported {
                Section {
                    if let dl = store.active {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Loading \(dl.version)…").font(.callout)
                            ProgressView(value: dl.progress)
                        }
                    } else if store.loadingIndex {
                        HStack { ProgressView(); Text("Fetching version list…").foregroundStyle(.secondary) }
                    } else if store.available.isEmpty {
                        Button { Task { await store.refreshIndex() } } label: {
                            Label("Load version list", systemImage: "arrow.down.circle")
                        }
                    } else {
                        ForEach(store.available) { release in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(release.version).font(.callout.weight(.medium))
                                    Text("\(release.asset.sizeMB, specifier: "%.1f") MB\(release.prerelease ? " · pre-release" : "")")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if store.isInstalled(release.version) {
                                    Label("Installed", systemImage: "checkmark.circle.fill")
                                        .labelStyle(.iconOnly).foregroundStyle(.green)
                                } else {
                                    Button("Download") { Task { await store.install(release) } }
                                        .disabled(store.active != nil)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Available versions")
                } footer: {
                    if let e = store.installError {
                        Text(LocalizedStringKey(e)).foregroundStyle(.red)
                    } else {
                        Text("Downloads the official Xray-core build from GitHub and verifies the checksum.")
                    }
                }
            }
        }
        .navigationTitle("Xray core")
        #if os(iOS)
        .toolbarTitleDisplayMode(.inline)
        #endif
        .task { if XrayCoreStore.isSupported && store.available.isEmpty { await store.refreshIndex() } }
        .confirmationDialog("Delete all downloaded cores?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
            Button("Delete all", role: .destructive) { store.removeAll() }
            Button("Cancel", role: .cancel) {}
        }
    }
}
