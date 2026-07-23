import SwiftUI

/// The "What's New" sheet shown once after an update. From the onboarding
/// design: a short list of what changed, an icon per item, one button out.
///
/// The copy lives in `WhatsNew.current`, keyed to the marketing version, so the
/// caller can decide whether this version's notes have been seen yet.
struct WhatsNewView: View {
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    VStack(spacing: 10) {
                        Text("Версия \(WhatsNew.version)")
                            .font(.caption.weight(.semibold))
                            .textCase(.uppercase)
                            .kerning(1.1)
                            .foregroundStyle(.tint)
                        Text("Что нового")
                            .font(.largeTitle.weight(.bold))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.bottom, 34)

                    VStack(alignment: .leading, spacing: 26) {
                        ForEach(Array(WhatsNew.items.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .top, spacing: 17) {
                                Image(systemName: item.icon)
                                    .font(.title.weight(.regular))
                                    .foregroundStyle(.tint)
                                    .frame(width: 38)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title).font(.headline)
                                    Text(item.body).font(.subheadline).foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 30)
                .padding(.top, 26)
                .padding(.bottom, 20)
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity)
            }

            Divider()
            Button(action: onDone) {
                Text("Понятно")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 15))
            .padding(.horizontal, 26).padding(.vertical, 14)
            .frame(maxWidth: 460)
        }
        .frame(maxWidth: .infinity)
        .background(Palette.groupedBackground.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

/// The release notes for the current version. Bump `version` and rewrite
/// `items` when the notes should show again.
enum WhatsNew {
    /// Shown to the user and compared against the last version they dismissed.
    /// Kept in sync with `CFBundleShortVersionString` by hand — the notes are
    /// written per release, not derived.
    static let version = "1.4"

    struct Item { let icon: String; let title: LocalizedStringKey; let body: LocalizedStringKey }

    // Computed rather than a stored static: LocalizedStringKey is not Sendable,
    // so a stored [Item] would need main-actor isolation the call sites do not
    // want. Rebuilding the small list per read costs nothing.
    static var items: [Item] {[
        Item(icon: "rectangle.connected.to.line.below", title: "Обзор сети",
             body: "Новый экран со всеми устройствами в вашей локальной сети."),
        Item(icon: "lock.shield", title: "Понятные разрешения",
             body: "Объясняем доступ к сети и геопозиции до системного запроса."),
        Item(icon: "gauge.with.dots.needle.67percent", title: "Быстрее тест скорости",
             body: "Загрузка и отдача теперь измеряются параллельно."),
        Item(icon: "clock.arrow.circlepath", title: "Расписания",
             body: "Запускайте проверки по расписанию и ведите историю аптайма.")
    ]}
}
