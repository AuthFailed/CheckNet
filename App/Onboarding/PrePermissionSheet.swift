import SwiftUI

/// The screen shown *before* iOS asks for a permission, so the system prompt
/// arrives with context rather than out of nowhere. From the onboarding design.
///
/// The anti-pattern this replaces is asking on launch: a prompt with no reason
/// gets denied, and then Bonjour and scanning are dead for good with no way
/// back that the user understands. Here the ask happens the first time a tool
/// that needs the permission is opened, the reason is stated in plain words,
/// and "Не сейчас" is an equal path — the tool simply does not run.
struct PrePermissionSheet: View {
    enum Kind {
        /// Bonjour, the network browser, the range scanner.
        case localNetwork
        /// Reading the Wi-Fi network name (SSID), which iOS only gives with
        /// location access.
        case location

        var icon: String {
            switch self {
            case .localNetwork: "wifi"
            case .location: "location"
            }
        }
        var title: LocalizedStringKey {
            switch self {
            case .localNetwork: "Разрешить доступ к локальной сети?"
            case .location: "Показать имя сети Wi-Fi?"
            }
        }
        var body: LocalizedStringKey {
            switch self {
            case .localNetwork: "Чтобы найти устройства в вашей сети, приложению нужен доступ к локальной сети."
            case .location: "iOS отдаёт название сети (SSID) только приложениям с доступом к геопозиции."
            }
        }
        var bullets: [(icon: String, text: LocalizedStringKey)] {
            switch self {
            case .localNetwork:
                [("house", "Сканируется только ваша локальная сеть — ничего за её пределами."),
                 ("iphone", "Всё происходит на устройстве, наружу данные не уходят."),
                 ("hand.thumbsup", "Дальше система покажет свой запрос — решение за вами.")]
            case .location:
                [("location", "Геопозиция нужна только чтобы прочитать имя Wi-Fi."),
                 ("iphone", "Координаты не сохраняются и не покидают устройство.")]
            }
        }
    }

    let kind: Kind
    /// The user chose to proceed — the caller triggers the real system prompt.
    var onAllow: () -> Void
    /// The user declined — the caller does not run the tool, and does not nag.
    var onNotNow: () -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var glyph: CGFloat = 40
    @ScaledMetric(relativeTo: .largeTitle) private var badge: CGFloat = 82

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Image(systemName: kind.icon)
                    .font(.system(size: glyph))
                    .foregroundStyle(.tint)
                    .frame(width: badge, height: badge)
                    .background(Color.accentColor.opacity(0.14),
                                in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding(.top, 8)
                    .padding(.bottom, 22)
                    .accessibilityHidden(true)

                Text(kind.title)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 12)

                Text(kind.body)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 22)

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(kind.bullets.enumerated()), id: \.offset) { _, bullet in
                        HStack(alignment: .top, spacing: 13) {
                            Image(systemName: bullet.icon)
                                .font(.body)
                                .foregroundStyle(.tint)
                                .frame(width: 26)
                                .accessibilityHidden(true)
                            Text(bullet.text)
                                .font(.subheadline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.bottom, 26)

                Button(action: onAllow) {
                    Text("Разрешить")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 15))

                Button(action: onNotNow) {
                    Text("Не сейчас")
                        .font(.body)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .padding(.top, 2)

                Text("«Не сейчас» — это нормально: проверка просто не запустится.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 26)
            .padding(.top, 20)
            .padding(.bottom, 32)
            .frame(maxWidth: 440)
            .frame(maxWidth: .infinity)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

/// Puts the pre-permission screen in front of a local-network tool the first
/// time it is opened, and only then. Attached to `ToolDestinationView`, so every
/// tool passes through it and only the ones that need the network trigger it.
struct LocalNetworkGate: ViewModifier {
    let tool: Tool

    #if os(iOS)
    @Environment(AppFlow.self) private var flow
    @State private var show = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                if tool.needsLocalNetwork && !flow.localNetworkAsked {
                    show = true
                }
            }
            .sheet(isPresented: $show) {
                PrePermissionSheet(kind: .localNetwork) {
                    // Asked once: the answer lives in iOS Settings from here on.
                    flow.localNetworkAsked = true
                    show = false
                    LocalNetworkPermission.shared.request { granted in
                        Task { @MainActor in flow.localNetworkDenied = !granted }
                    }
                } onNotNow: {
                    flow.localNetworkAsked = true
                    show = false
                }
            }
    }
    #else
    // No Local Network privacy prompt on macOS.
    func body(content: Content) -> some View { content }
    #endif
}
