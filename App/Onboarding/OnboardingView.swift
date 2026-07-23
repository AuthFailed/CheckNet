import SwiftUI

/// First-launch onboarding: three pages that say what the app is, that it keeps
/// everything on the device, and that nothing automated turns itself on. Built
/// from the design in the CheckNet onboarding spec.
///
/// A paged `TabView`, not a custom pager, so the swipe, the page dots and
/// VoiceOver's page semantics come from the system. Content is capped at a
/// readable measure and centred rather than stretched, which is what keeps it
/// right on an iPad and a Mac window as well as a phone.
struct OnboardingView: View {
    /// Called when the user finishes or skips — the caller records that
    /// onboarding is done.
    var onFinish: () -> Void

    @State private var page = 0
    @Environment(\.dynamicTypeSize) private var typeSize

    private struct Page: Identifiable {
        let id = UUID()
        let icon: String
        let tag: LocalizedStringKey
        let title: LocalizedStringKey
        let body: LocalizedStringKey
        let bullets: [(icon: String, text: LocalizedStringKey)]
    }

    private let pages: [Page] = [
        Page(icon: "wrench.and.screwdriver",
             tag: "Каталог проверок",
             title: "Все проверки в одном месте",
             body: "Пинг, трассировка, DNS, TLS, скорость, сканер сети, Bonjour, мониторинг — и у каждой честное объяснение, что она делает и зачем.",
             bullets: [("info.circle", "Кнопка ⓘ у каждой проверки — простыми словами"),
                       ("list.bullet", "Чистый список как в Настройках iOS")]),
        Page(icon: "lock.shield",
             tag: "Приватность",
             title: "Всё считается на устройстве",
             body: "Диагностика выполняется прямо на вашем iPhone. Наружу ничего не уходит — результаты остаются у вас.",
             bullets: [("iphone", "Данные не покидают устройство"),
                       ("server.rack", "Вебхуки — только на ВАШ сервер, если вы их включите")]),
        Page(icon: "clock.arrow.circlepath",
             tag: "Автоматизация — по желанию",
             title: "Автоматизация, когда сами захотите",
             body: "Расписания, вебхуки на свой сервер и мониторинг хостов. Ничего не включается само — вы решаете, что и когда запускать.",
             bullets: [("calendar.badge.checkmark", "Расписания и мониторинг — по вашему выбору"),
                       ("switch.2", "По умолчанию всё выключено")])
    ]

    private var isLast: Bool { page == pages.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Пропустить", action: onFinish)
                    .font(.body)
                    .padding(.horizontal, 6)
                    .frame(minHeight: 44)
            }
            .padding(.horizontal, 20)

            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                    pageView(page)
                        .tag(index)
                }
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .never))
            #endif

            VStack(spacing: 26) {
                PageDots(count: pages.count, current: page) { page = $0 }

                Button {
                    if isLast { onFinish() } else { withAnimation { page += 1 } }
                } label: {
                    Text(isLast ? "Начать" : "Далее")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 15))
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 44)
            .frame(maxWidth: 460)
        }
        .frame(maxWidth: .infinity)
        .background(Palette.groupedBackground.ignoresSafeArea())
    }

    private func pageView(_ page: Page) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                Image(systemName: page.icon)
                    .font(.system(size: 50))
                    .foregroundStyle(.tint)
                    .frame(width: 104, height: 104)
                    .background(Color.accentColor.opacity(0.14),
                                in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .padding(.bottom, 34)
                    .accessibilityHidden(true)

                Text(page.tag)
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .kerning(1.2)
                    .foregroundStyle(.tint)
                    .padding(.bottom, 14)

                Text(page.title)
                    .font(.title.weight(.bold))
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 16)

                Text(page.body)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                VStack(spacing: 12) {
                    ForEach(Array(page.bullets.enumerated()), id: \.offset) { _, bullet in
                        HStack(spacing: 13) {
                            Image(systemName: bullet.icon)
                                .font(.body)
                                .foregroundStyle(.tint)
                                .frame(width: 24)
                                .accessibilityHidden(true)
                            Text(bullet.text)
                                .font(.subheadline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 15).padding(.vertical, 13)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Palette.hairline, lineWidth: Palette.hairlineWidth))
                    }
                }
                .padding(.top, 26)
            }
            .padding(.horizontal, 40)
            .frame(maxWidth: 460)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }
}

/// The page indicator, its own control so a tap on a dot jumps to that page and
/// VoiceOver reads a real position.
private struct PageDots: View {
    let count: Int
    let current: Int
    let go: (Int) -> Void
    @ScaledMetric(relativeTo: .caption) private var dot: CGFloat = 9

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                Button { go(index) } label: {
                    Circle()
                        .fill(index == current ? Color.accentColor : Color.secondary.opacity(0.4))
                        .frame(width: dot, height: dot)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Страница \(index + 1) из \(count)")
                .accessibilityAddTraits(index == current ? [.isSelected] : [])
            }
        }
        .accessibilityElement(children: .contain)
    }
}
