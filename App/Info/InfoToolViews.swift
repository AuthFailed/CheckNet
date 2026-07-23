import SwiftUI
import NetworkKit

// MARK: - Host → IP

struct HostToIPView: View {
    var presetHost: String? = nil
    var autostart = false
    @State private var host = "apple.com"
    @State private var run = ToolRunModel<Resolved>()

    /// The forward lookup plus the reverse PTR names gathered for each address.
    private struct Resolved: Sendable, Equatable {
        let lookup: HostLookupResult
        let reverse: [String: String]
    }

    private func start() {
        let target = host.trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty, !run.isRunning else { return }
        run.start {
            let res = try await HostLookup.resolve(host: target)
            var reverse: [String: String] = [:]
            for addr in res.addresses {
                if let name = try? await ReverseDNS.lookup(ip: addr.ip) { reverse[addr.ip] = name }
            }
            return Resolved(lookup: res, reverse: reverse)
        }
    }

    var body: some View {
        ToolScaffold {
            HostInputBar(text: $host, placeholder: "Домен", icon: "arrow.right.circle",
                         disabled: run.isRunning, savedHostTool: .hostToIP) { start() }
            if let error = run.errorMessage {
                ErrorCard(message: error) { start() }
            } else if run.value == nil, run.isRunning {
                ProgressView().padding(.top, 40)
            }
        } content: {
            if run.errorMessage == nil, let resolved = run.value {
                addressCard(resolved)
            }
        } bottom: {
            RunButton(title: "Разрешить", running: run.isRunning,
                      disabled: host.trimmingCharacters(in: .whitespaces).isEmpty) {
                start()
            }
        }
        .animation(.snappy, value: run.value)
        .navigationTitle("Host → IP")
        .toolTitleDisplayMode()
        .onAppear {
            if let presetHost { host = presetHost }
            if autostart { start() }
        }
    }

    private func addressCard(_ resolved: Resolved) -> some View {
        let result = resolved.lookup
        return VStack(alignment: .leading, spacing: 6) {
            SectionCaption(text: "\(result.addresses.count) адресов")
            VStack(spacing: 0) {
                ForEach(Array(result.addresses.enumerated()), id: \.element.id) { idx, addr in
                    HStack {
                        Text(addr.family == .ipv4 ? "v4" : "v6")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(addr.family == .ipv4 ? .blue : .purple)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background((addr.family == .ipv4 ? Color.blue : Color.purple).opacity(0.12),
                                        in: RoundedRectangle(cornerRadius: 5))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(addr.ip).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                            if let name = resolved.reverse[addr.ip] {
                                Text(name).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    if idx < result.addresses.count - 1 { Divider().padding(.leading, 14) }
                }
            }
            .card()
        }
    }
}

// MARK: - Reverse DNS

struct ReverseDNSView: View {
    var presetHost: String? = nil
    var autostart = false
    @State private var ip = "8.8.8.8"
    // The result is the PTR name, itself optional: a successful run with no
    // record is `.success(nil)` — distinct from "not run yet" (.idle).
    @State private var run = ToolRunModel<String?>()

    private func start() {
        let target = ip.trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty, !run.isRunning else { return }
        run.start { try await ReverseDNS.lookup(ip: target) }
    }

    var body: some View {
        ToolScaffold {
            HostInputBar(text: $ip, placeholder: "IP-адрес", icon: "arrow.uturn.backward",
                         disabled: run.isRunning, savedHostTool: .reverseDns) { start() }
            if let error = run.errorMessage {
                ErrorCard(message: error) { start() }
            } else if run.isRunning {
                ProgressView().padding(.top, 40)
            }
        } content: {
            if run.errorMessage == nil, case .success(let name) = run.phase {
                VStack(spacing: 0) {
                    InfoRow(label: "IP", value: ip, mono: true)
                    Divider().padding(.leading, 14)
                    InfoRow(label: "PTR", value: name ?? "нет записи", mono: true,
                            valueColor: name == nil ? .secondary : .primary)
                }
                .card()
            }
        } bottom: {
            RunButton(title: "Найти PTR", running: run.isRunning,
                      disabled: ip.trimmingCharacters(in: .whitespaces).isEmpty) {
                start()
            }
        }
        .navigationTitle("Обратный DNS")
        .toolTitleDisplayMode()
        .onAppear {
            if let presetHost { ip = presetHost }
            if autostart { start() }
        }
    }
}

// MARK: - Interfaces

struct InterfacesView: View {
    @State private var interfaces: [NetworkInterface] = []

    var body: some View {
        List {
            ForEach(interfaces) { iface in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(iface.friendlyName).font(.headline)
                        Spacer()
                        StatusDot(level: iface.isUp ? .ok : .unknown,
                                  label: iface.isUp ? "Интерфейс активен" : "Интерфейс не активен")
                    }
                    LabeledContent("Адрес") { Text(iface.address).monospaced().textSelection(.enabled) }
                        .font(.callout)
                    if let mask = iface.netmask {
                        LabeledContent("Маска") { Text(mask).monospaced() }.font(.callout)
                    }
                    LabeledContent("Семейство") { Text(iface.family == .ipv4 ? "IPv4" : "IPv6") }.font(.callout)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Интерфейсы")
        #if os(iOS)
        .toolbarTitleDisplayMode(.inline)
        #endif
        .overlay {
            if interfaces.isEmpty {
                ContentUnavailableView("Нет активных интерфейсов", systemImage: "network.slash")
            }
        }
        .task { interfaces = NetworkInterfaces.list() }
        .refreshable { interfaces = NetworkInterfaces.list() }
    }
}
