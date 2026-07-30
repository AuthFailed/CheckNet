import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SavedHostsStore.self) private var savedHosts
    @Environment(SavedSubscriptionsStore.self) private var savedSubscriptions
    @Environment(XrayCoreStore.self) private var xrayCores
    @State private var showHistory = false
    @State private var permissionResult: String?

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $settings.theme) {
                        ForEach(AppTheme.allCases) { Text(LocalizedStringKey($0.label)).tag($0) }
                    }
                    Picker("Language", selection: $settings.language) {
                        ForEach(AppLanguage.allCases) { Text($0.label).tag($0) }
                    }
                }

                Section {
                    NavigationLink {
                        SavedHostsEditor(kind: .domain)
                    } label: {
                        Label {
                            LabeledContent("Domains", value: "\(savedHosts.savedDomains.count)")
                        } icon: { Image(systemName: "globe") }
                    }
                    NavigationLink {
                        SavedHostsEditor(kind: .ip)
                    } label: {
                        Label {
                            LabeledContent("IP addresses", value: "\(savedHosts.savedIPs.count)")
                        } icon: { Image(systemName: "number") }
                    }
                    NavigationLink {
                        SavedSubscriptionsEditor()
                    } label: {
                        Label {
                            LabeledContent("VPN subscriptions", value: "\(savedSubscriptions.items.count)")
                        } icon: { Image(systemName: "list.bullet.rectangle") }
                    }
                    NavigationLink {
                        XrayCoresEditor()
                    } label: {
                        Label {
                            LabeledContent("Xray core") {
                                Text(xrayCores.installed.isEmpty
                                     ? (XrayCoreStore.isSupported ? "no" : "Mac")
                                     : "\(xrayCores.installed.count)")
                                .foregroundStyle(.secondary)
                            }
                        } icon: { Image(systemName: "shippingbox") }
                    }
                    NavigationLink {
                        HostSharingView()
                    } label: {
                        Label("Sharing and import", systemImage: "square.and.arrow.up")
                    }
                    LabeledContent {
                        Text(CloudHostSync.isAvailable ? "Enabled" : "Unavailable")
                            .foregroundStyle(.secondary)
                    } label: {
                        Label("iCloud sync", systemImage: "icloud")
                    }
                } header: {
                    Text("Saved hosts")
                } footer: {
                    Text("Saved hosts and favorites sync via your iCloud across your devices.")
                }

                Section {
                    #if !os(macOS)
                    Toggle("Live Activity in Dynamic Island", isOn: $settings.liveActivitiesEnabled)
                    Toggle("Haptic feedback", isOn: $settings.hapticsEnabled)
                    #endif
                    Toggle("Reverse DNS by default", isOn: $settings.reverseDNSByDefault)
                    Toggle("Warn about scanning checks", isOn: $settings.confirmSensitiveTests)
                    Button {
                        showHistory = true
                    } label: {
                        Label("Check history", systemImage: "clock.arrow.circlepath")
                    }
                } header: {
                    Text("Checks")
                } footer: {
                    Text("Scanning ports and IP ranges on others' networks may be treated as an attack. When enabled, the app asks for consent before running such checks.")
                }

                Section("Automation") {
                    NavigationLink {
                        ScheduledTasksView()
                    } label: {
                        Label("Schedule", systemImage: "clock.arrow.2.circlepath")
                    }
                    NavigationLink {
                        NetworkProfilesView()
                    } label: {
                        Label("Network profiles", systemImage: "wifi")
                    }
                    NavigationLink {
                        WebhookSettingsView()
                    } label: {
                        Label("Webhooks", systemImage: "paperplane")
                    }
                }

                Section {
                    Button {
                        // The callback arrives on the permission helper's own
                        // queue, so hop back before touching view state.
                        LocalNetworkPermission.shared.request { granted in
                            Task { @MainActor in
                                permissionResult = granted
                                    ? "Local network access is active."
                                    : "Local network access not granted — allow it in iOS Settings."
                            }
                        }
                    } label: {
                        Label("Request local network access", systemImage: "wifi")
                    }
                    if let permissionResult {
                        Text(LocalizedStringKey(permissionResult)).font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Permissions")
                } footer: {
                    Text("The network scanner, device overview, and Bonjour require local network access. On iOS, without it the checks may silently fail.")
                }

                Section("About") {
                    LabeledContent("Version", value: appVersion)
                    LabeledContent("Tools", value: "\(Tool.allCases.filter(\.isImplemented).count)")
                    Link(destination: URL(string: "https://ru.wikipedia.org/wiki/Ping")!) {
                        Label("How the checks work", systemImage: "questionmark.circle")
                    }
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showHistory) {
                HistoryView().presentationDetents([.large])
            }
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}

/// Add/edit/delete saved hosts of one kind (IP or domain).
struct SavedHostsEditor: View {
    enum Kind { case ip, domain
        var title: String { self == .ip ? "IP addresses" : "Domains" }
        var placeholder: String { self == .ip ? "8.8.8.8" : "example.com" }
        var icon: String { self == .ip ? "number" : "globe" }
    }
    let kind: Kind
    @Environment(SavedHostsStore.self) private var store
    @State private var newName = ""
    @State private var newValue = ""

    private var items: [SavedHost] { kind == .ip ? store.savedIPs : store.savedDomains }

    var body: some View {
        Form {
            Section("Add") {
                TextField("Name (optional)", text: $newName)
                HStack {
                    Image(systemName: kind.icon).foregroundStyle(.secondary)
                    TextField(kind.placeholder, text: $newValue)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(kind == .ip ? .numbersAndPunctuation : .URL)
                        #endif
                }
                Button("Save") { add() }
                    .disabled(!isValid)
            }

            Section("Saved") {
                if items.isEmpty {
                    ContentUnavailableView(
                        "Empty for now",
                        systemImage: kind.icon,
                        description: Text("Saved addresses show up in the bookmarks menu on every screen with an input field.")
                    )
                } else {
                    ForEach(items) { host in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(host.name).font(.body)
                            Text(host.value).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { offsets in
                        for i in offsets { store.remove(items[i]) }
                    }
                }
            }
        }
        .navigationTitle(LocalizedStringKey(kind.title))
        #if os(iOS)
        .toolbarTitleDisplayMode(.inline)
        #endif
    }

    private var isValid: Bool {
        let v = newValue.trimmingCharacters(in: .whitespaces)
        guard !v.isEmpty else { return false }
        return kind == .ip ? SavedHostsStore.isIP(v) : !SavedHostsStore.isIP(v) && v.contains(".")
    }

    private func add() {
        store.add(name: newName, value: newValue, tool: nil)
        newName = ""; newValue = ""
    }
}
