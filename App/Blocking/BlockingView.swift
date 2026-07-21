import SwiftUI
import NetworkKit

/// How the checks are grouped in the list.
///
/// The original request was a second row of tabs at the bottom, but that slot
/// already belongs to the root `TabView` and a nested tab bar reads as foreign
/// on iOS 26. Sections carry the same structure using the system list.
enum BlockingSection: String, CaseIterable, Identifiable {
    case restrictions, availability, degradation, dns

    var id: String { rawValue }

    var title: String {
        switch self {
        // Not "Блокировки" — that's the tab title, and the repeat reads as a bug.
        case .restrictions: "Фильтрация"
        case .availability: "Недоступность"
        case .degradation: "Деградация"
        case .dns: "DNS"
        }
    }

    var footer: String? {
        switch self {
        case .restrictions: "Проверки сравнивают ваше соединение с эталоном и показывают, что именно ограничивает сеть."
        case .availability: "Что именно недоступно — по провайдерам, сервисам и серверам уведомлений."
        case .degradation: "Соединение устанавливается, но рвётся или замедляется в процессе."
        case .dns: nil
        }
    }

    var checks: [BlockingCheck] {
        switch self {
        case .restrictions: [.sniBlocking, .ipBlocking, .httpBlock, .whitelist]
        case .availability: []
        case .degradation: [.transferCutoff, .siberian]
        case .dns: [.dnsSpoofing]
        }
    }
}

/// The "Блокировки" tab — checks that reveal local ISP restrictions the user's
/// own connection is subject to (transparency/diagnostics).
struct BlockingView: View {
    @State private var path: [BlockingRoute] = []
    @State private var portal: CaptivePortalResult?
    @State private var checkingPortal = false

    var body: some View {
        NavigationStack(path: $path) {
            List {
                // A captive portal rewrites every request, so surface it first —
                // otherwise every check below reports a false positive.
                if let portal, portal.state != .open {
                    Section {
                        captivePortalBanner(portal)
                    }
                }

                ForEach(BlockingSection.allCases) { section in
                    Section {
                        if section == .availability {
                            NavigationLink(value: BlockingRoute.reachability) {
                                sweepRow
                            }
                        }
                        ForEach(section.checks) { check in
                            row(check)
                                .contentShape(.rect)
                                .onTapGesture { path.append(.check(check)) }
                        }
                    } header: {
                        Text(LocalizedStringKey(section.title))
                    } footer: {
                        if let footer = section.footer {
                            Text(LocalizedStringKey(footer))
                        }
                    }
                }

                Section {
                    EmptyView()
                } footer: {
                    Text("Только диагностика: приложение показывает, какие ограничения применяет сеть, и не помогает их обходить.")
                }
            }
            .navigationTitle("Блокировки")
            .navigationDestination(for: BlockingRoute.self) { route in
                switch route {
                case .check(let check): BlockingCheckView(check: check)
                case .reachability: ReachabilityView()
                }
            }
            .task { await checkPortal() }
            .refreshable { await checkPortal() }
        }
    }

    private func checkPortal() async {
        guard !checkingPortal else { return }
        checkingPortal = true
        portal = await CaptivePortalCheck().run()
        checkingPortal = false
    }

    private func captivePortalBanner(_ portal: CaptivePortalResult) -> some View {
        HStack(spacing: 13) {
            Image(systemName: "wifi.exclamationmark")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text("Сеть перехватывает трафик").font(.headline)
                Text(LocalizedStringKey(portal.detail)).font(.caption).foregroundStyle(.secondary)
                Text("Пока не выполнен вход, проверки ниже могут ошибаться.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(Color.orange.opacity(0.12))
    }

    private var sweepRow: some View {
        HStack(spacing: 13) {
            Image(systemName: "network")
                .font(.system(size: 17))
                .foregroundStyle(.tint)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("Доступность узлов").foregroundStyle(.primary)
                Text("Провайдеры, сервисы, push-уведомления").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func row(_ check: BlockingCheck) -> some View {
        HStack(spacing: 13) {
            Image(systemName: check.systemImage)
                .font(.system(size: 17))
                .foregroundStyle(.tint)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(check.title)).foregroundStyle(.primary)
                Text(LocalizedStringKey(check.subtitle)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            InfoButton(title: check.title, systemImage: check.systemImage, message: check.explanation)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

enum BlockingRoute: Hashable {
    case check(BlockingCheck)
    case reachability
}
