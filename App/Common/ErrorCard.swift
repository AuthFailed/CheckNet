import SwiftUI

/// The one way a tool screen reports a failure.
///
/// Before this there were three: a `.failed` phase, a loose `errorMessage`
/// string, and — worst — a `try?` that dropped the error and left the screen
/// looking idle. A check that fails silently is the one users report as a
/// button that does nothing.
///
/// The status is never carried by colour alone: an icon and the word "Ошибка"
/// say it too, so it survives dark mode, colour blindness and a screenshot.
struct ErrorCard: View {
    let message: String
    /// What the user can actually try next, when the failure suggests something.
    var hint: String?
    /// Omitted when the action that failed cannot simply be repeated.
    var retry: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text("Ошибка").font(.subheadline.weight(.semibold))
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }

            Text(LocalizedStringKey(message))
                .font(.callout)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if let hint {
                Text(LocalizedStringKey(hint))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let retry {
                Button {
                    retry()
                } label: {
                    Label("Повторить", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .card()
        // One announcement instead of four fragments; the retry button stays a
        // separate element so VoiceOver can still reach it.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Ошибка: \(message)"))
    }
}

#Preview {
    VStack(spacing: 16) {
        ErrorCard(message: "Хост не найден", hint: "Проверьте написание имени и подключение к сети") {}
        ErrorCard(message: "Соединение прервано по таймауту")
    }
    .padding()
    .background(Palette.groupedBackground)
}
