import SwiftUI
import NetworkKit

// MARK: - Host → IP

@MainActor
@Observable
final class HostToIPModel {
    var host = "apple.com"
    private(set) var isRunning = false
    private(set) var result: HostLookupResult?
    private(set) var reverse: [String: String] = [:]
    private(set) var errorMessage: String?

    func run() async {
        let target = host.trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty else { return }
        isRunning = true; errorMessage = nil; result = nil; reverse = [:]
        do {
            let res = try await HostLookup.resolve(host: target)
            result = res
            for addr in res.addresses {
                if let name = try? await ReverseDNS.lookup(ip: addr.ip) {
                    reverse[addr.ip] = name
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isRunning = false
    }
}

struct HostToIPView: View {
    var presetHost: String? = nil
    var autostart = false
    @State private var model = HostToIPModel()

    var body: some View {
        ToolScaffold {
            HostInputBar(text: $model.host, placeholder: "Домен", icon: "arrow.right.circle",
                         disabled: model.isRunning, savedHostTool: .hostToIP) { Task { await model.run() } }
            if let error = model.errorMessage {
                ErrorCard(message: error) { Task { await model.run() } }
            } else if model.result == nil, model.isRunning {
                ProgressView().padding(.top, 40)
            }
        } content: {
            if model.errorMessage == nil, let result = model.result {
                addressCard(result)
            }
        } bottom: {
            RunButton(title: "Разрешить", running: model.isRunning,
                      disabled: model.host.trimmingCharacters(in: .whitespaces).isEmpty) {
                if model.isRunning { return }; Task { await model.run() }
            }
        }
        .animation(.snappy, value: model.result)
        .navigationTitle("Host → IP")
        .toolTitleDisplayMode()
        .onAppear {
            if let presetHost { model.host = presetHost }
            if autostart { Task { await model.run() } }
        }
    }

    private func addressCard(_ result: HostLookupResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
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
                            if let name = model.reverse[addr.ip] {
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

@MainActor
@Observable
final class ReverseDNSModel {
    var ip = "8.8.8.8"
    private(set) var isRunning = false
    private(set) var name: String?
    private(set) var didRun = false
    private(set) var errorMessage: String?

    func run() async {
        let target = ip.trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty else { return }
        isRunning = true; errorMessage = nil; name = nil; didRun = false
        do {
            name = try await ReverseDNS.lookup(ip: target)
            didRun = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isRunning = false
    }
}

struct ReverseDNSView: View {
    var presetHost: String? = nil
    var autostart = false
    @State private var model = ReverseDNSModel()

    var body: some View {
        ToolScaffold {
            HostInputBar(text: $model.ip, placeholder: "IP-адрес", icon: "arrow.uturn.backward",
                         disabled: model.isRunning, savedHostTool: .reverseDns) { Task { await model.run() } }
            if let error = model.errorMessage {
                ErrorCard(message: error) { Task { await model.run() } }
            } else if !model.didRun, model.isRunning {
                ProgressView().padding(.top, 40)
            }
        } content: {
            if model.errorMessage == nil, model.didRun {
                VStack(spacing: 0) {
                    InfoRow(label: "IP", value: model.ip, mono: true)
                    Divider().padding(.leading, 14)
                    InfoRow(label: "PTR", value: model.name ?? "нет записи", mono: true,
                            valueColor: model.name == nil ? .secondary : .primary)
                }
                .card()
            }
        } bottom: {
            RunButton(title: "Найти PTR", running: model.isRunning,
                      disabled: model.ip.trimmingCharacters(in: .whitespaces).isEmpty) {
                if model.isRunning { return }; Task { await model.run() }
            }
        }
        .navigationTitle("Обратный DNS")
        .toolTitleDisplayMode()
        .onAppear {
            if let presetHost { model.ip = presetHost }
            if autostart { Task { await model.run() } }
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
                        Circle().fill(iface.isUp ? .green : .gray).frame(width: 8, height: 8)
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
