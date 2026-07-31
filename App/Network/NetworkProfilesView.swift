import SwiftUI
import NetworkKit

/// Manage per-network check profiles and run the one matching the current Wi-Fi.
struct NetworkProfilesView: View {
    @Environment(NetworkProfileStore.self) private var store
    @State private var editing: NetworkProfile?
    @State private var runState: RunState = .idle

    enum RunState: Equatable {
        case idle
        case reading
        case noMatch(WiFiIdentity)
        case unavailable(reason: String)
        case running(WiFiIdentity)
        case done(WiFiIdentity, summary: String)
    }

    var body: some View {
        Form {
            // Offering a button that cannot succeed is worse than saying why.
            // Without the Access Wi-Fi Information entitlement iOS never reports
            // the SSID, so the screen explains that instead — and does not ask
            // for location, which is only needed for a lookup that can't happen.
            if CurrentNetwork.isSSIDReadable {
                Section {
                    Button {
                        Task { await runForCurrentNetwork() }
                    } label: {
                        Label("Check current network", systemImage: "wifi")
                    }
                    .disabled(isBusy)
                    statusRow
                } footer: {
                    Text("Reads the name of the current Wi-Fi network and runs the profile for it. Reading the network name requires the app’s Wi-Fi entitlement and location permission (an iOS requirement).")
                }
            } else {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Network detection unavailable")
                                .font(.callout.weight(.medium))
                                .foregroundStyle(.primary)
                            Text("iOS gives the Wi-Fi network name only to apps with the “Access Wi-Fi Information” entitlement, which only a paid developer account can sign. Automatic network detection is therefore turned off in this build.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "wifi.exclamationmark").foregroundStyle(.orange)
                    }
                } footer: {
                    Text("The profiles below are still useful: the “When I connect to Wi-Fi …” condition is evaluated by the system itself in Shortcuts, so an automation can start a check without the network-name entitlement.")
                }
            }

            Section("Profiles") {
                if store.profiles.isEmpty {
                    Text("No profiles yet").foregroundStyle(.secondary)
                } else {
                    ForEach(store.profiles) { profile in
                        Button { editing = profile } label: { profileRow(profile) }
                            .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        for i in offsets { store.remove(store.profiles[i]) }
                    }
                }
            }

            Section {
                Button {
                    editing = NetworkProfile(ssid: "", checkIDs: [])
                } label: {
                    Label("Add profile", systemImage: "plus")
                }
            } footer: {
                Text("Running a check when you join a network is set up in Shortcuts: an automation “When I connect to Wi-Fi …” → “Check for blocking”. iOS doesn’t wake the app on a network change by itself.")
            }
        }
        .navigationTitle("Network profiles")
        #if os(iOS)
        .toolbarTitleDisplayMode(.inline)
        #endif
        .sheet(item: $editing) { profile in
            NetworkProfileEditor(profile: profile)
        }
    }

    private var isBusy: Bool {
        if case .reading = runState { return true }
        if case .running = runState { return true }
        return false
    }

    @ViewBuilder private var statusRow: some View {
        switch runState {
        case .idle:
            EmptyView()
        case .reading:
            HStack { ProgressView(); Text("Detecting network…").font(.caption).foregroundStyle(.secondary) }
        case .noMatch(let info):
            VStack(alignment: .leading, spacing: 6) {
                networkIdentity(info)
                Text("There's no profile for this network.").font(.caption).foregroundStyle(.secondary)
            }
        case .unavailable(let reason):
            Text(LocalizedStringKey(reason)).font(.caption).foregroundStyle(.orange)
        case .running(let info):
            VStack(alignment: .leading, spacing: 6) {
                networkIdentity(info)
                HStack { ProgressView(); Text("Checking profile…").font(.caption).foregroundStyle(.secondary) }
            }
        case .done(let info, let summary):
            VStack(alignment: .leading, spacing: 6) {
                networkIdentity(info)
                Text(summary).font(.caption)
            }
        }
    }

    /// The App-Store-safe Wi-Fi identity iOS exposes: name, BSSID, security.
    /// (Signal level and channel are not available to apps on iOS — those live
    /// in the macOS Wi-Fi tools.)
    private func networkIdentity(_ info: WiFiIdentity) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            LabeledContent("Network", value: info.ssid)
            if let bssid = info.bssidDisplay {
                LabeledContent("BSSID") { Text(bssid).monospaced() }
            }
            LabeledContent("Security") {
                Label {
                    Text(LocalizedStringKey(info.securityLabel))
                } icon: {
                    Image(systemName: info.isSecure ? "lock.fill" : "lock.open")
                }
                .labelStyle(.titleAndIcon)
                .foregroundStyle(info.isSecure ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
            }
        }
        .font(.caption)
    }

    private func profileRow(_ profile: NetworkProfile) -> some View {
        HStack {
            Image(systemName: profile.isEnabled ? "wifi" : "wifi.slash")
                .foregroundStyle(profile.isEnabled ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.ssid.isEmpty ? "Untitled" : profile.ssid)
                Text("Checks: \(profile.checkIDs.count)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
    }

    private func runForCurrentNetwork() async {
        runState = .reading
        let result = await CurrentNetwork.current()
        let info: WiFiIdentity
        switch result {
        case .connected(let network):
            info = network
        case .restricted(let reason), .unavailable(let reason):
            runState = .unavailable(reason: reason)
            return
        }

        guard let profile = store.profile(forSSID: info.ssid) else {
            runState = .noMatch(info)
            return
        }

        runState = .running(info)
        var restricted = 0
        for id in profile.checkIDs {
            guard let check = BlockingCheck(rawValue: id) else { continue }
            let target = profile.target.isEmpty ? check.defaultTarget : profile.target
            let finding = await check.run(target: target)
            if finding.verdict == .restricted { restricted += 1 }
            WebhookReporter.reportBlocking(check: id, target: target, finding: finding, eventPrefix: "profile")
        }
        let summary = restricted == 0
            ? "No restrictions found (\(profile.checkIDs.count) checks)."
            : "Restrictions found: \(restricted) of \(profile.checkIDs.count)."
        runState = .done(info, summary: summary)
    }
}

/// Create or edit a profile.
struct NetworkProfileEditor: View {
    @Environment(NetworkProfileStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: NetworkProfile
    private let isNew: Bool

    init(profile: NetworkProfile) {
        _draft = State(initialValue: profile)
        isNew = profile.ssid.isEmpty && profile.checkIDs.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Network") {
                    TextField("Wi-Fi name (SSID)", text: $draft.ssid)
                        .autocorrectionDisabled()
                    Toggle("Profile active", isOn: $draft.isEnabled)
                }

                Section("Checks") {
                    ForEach(BlockingCheck.allCases) { check in
                        Button {
                            toggle(check)
                        } label: {
                            HStack {
                                Image(systemName: draft.checkIDs.contains(check.rawValue) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(draft.checkIDs.contains(check.rawValue) ? Color.accentColor : .secondary)
                                Text(LocalizedStringKey(check.title))
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section("Target (optional)") {
                    TextField("Default domain for each check", text: $draft.target)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                }
            }
            .navigationTitle(isNew ? "New profile" : "Profile")
            #if os(iOS)
            .toolbarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(draft.ssid.trimmingCharacters(in: .whitespaces).isEmpty || draft.checkIDs.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func toggle(_ check: BlockingCheck) {
        if let index = draft.checkIDs.firstIndex(of: check.rawValue) {
            draft.checkIDs.remove(at: index)
        } else {
            draft.checkIDs.append(check.rawValue)
        }
    }

    private func save() {
        draft.ssid = draft.ssid.trimmingCharacters(in: .whitespaces)
        if store.profiles.contains(where: { $0.id == draft.id }) {
            store.update(draft)
        } else {
            store.add(draft)
        }
        dismiss()
    }
}
