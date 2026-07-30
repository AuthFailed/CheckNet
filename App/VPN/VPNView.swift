import SwiftUI

/// Routing value for the VPN tab.
enum VPNRoute: Hashable {
    case tool(VPNTool)
}

/// The **VPN** tab — operator tooling for the Xray / Reality / mihomo / Happ
/// ecosystem. Mirrors the Блокировки tab: a system list of tools, each with an
/// ⓘ description; unbuilt tools push a plain placeholder rather than a
/// half-working screen.
struct VPNView: View {
    @State private var path: [VPNRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(Array(VPNCatalog.sections.enumerated()), id: \.element.id) { index, section in
                    Section {
                        ForEach(section.tools) { tool in
                            NavigationLink(value: VPNRoute.tool(tool)) {
                                row(tool)
                            }
                        }
                    } header: {
                        Text(LocalizedStringKey(section.title))
                    } footer: {
                        if index == VPNCatalog.sections.count - 1 {
                            Text("Диагностика и работа с конфигами для владельцев VPN. Приложение не обходит блокировки — оно помогает настроить и проверить свой сервер.")
                        }
                    }
                }
            }
            .navigationTitle("VPN")
            .navigationDestination(for: VPNRoute.self) { route in
                switch route {
                case .tool(let tool):
                    if tool.isImplemented {
                        destination(for: tool)
                    } else {
                        VPNPlaceholderView(tool: tool)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func destination(for tool: VPNTool) -> some View {
        switch tool {
        case .happRouting:
            HappRoutingView()
        case .happDecrypt:
            HappDecryptView()
        case .incyLink:
            IncyLinkView()
        case .subscription:
            SubscriptionView()
        case .sniCheck:
            RealitySNIView()
        case .realityScanner:
            RealityScannerView()
        case .clientHeaders:
            ClientHeadersView()
        case .geoData:
            GeoDataView()
        case .xrayCheck:
            XrayCheckView()
        default:
            VPNPlaceholderView(tool: tool)
        }
    }

    private func row(_ tool: VPNTool) -> some View {
        HStack(spacing: 13) {
            Image(systemName: tool.systemImage)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(tool.title)).foregroundStyle(.primary)
                Text(LocalizedStringKey(tool.subtitle)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            InfoButton(title: tool.title, systemImage: tool.systemImage, message: tool.info)
        }
        .padding(.vertical, 2)
    }
}
