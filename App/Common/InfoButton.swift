import SwiftUI

/// A small ⓘ button that reveals a short "what & why" description of a check.
/// Used in the catalog rows, the Блокировки rows, and inside each tool screen.
struct InfoButton: View {
    let title: String
    let systemImage: String
    let message: String
    var note: String? = nil
    @State private var show = false

    var body: some View {
        Button {
            show = true
        } label: {
            Image(systemName: "info.circle")
                .font(.body)
                .foregroundStyle(.secondary)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Об инструменте")
        .sheet(isPresented: $show) {
            InfoSheet(title: title, systemImage: systemImage, message: message, note: note)
        }
    }
}

/// The bottom sheet describing what a check does and why it's useful.
struct InfoSheet: View {
    let title: String
    let systemImage: String
    let message: String
    var note: String? = nil
    @Environment(\.dismiss) private var dismiss
    // A header badge keeps its proportions with text size instead of a fixed
    // 28 pt glyph in a 54 pt tile that stops matching at large sizes.
    @ScaledMetric(relativeTo: .title2) private var glyph: CGFloat = 28
    @ScaledMetric(relativeTo: .title2) private var badge: CGFloat = 54

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 14) {
                        Image(systemName: systemImage)
                            .font(.system(size: glyph))
                            .foregroundStyle(.tint)
                            .frame(width: badge, height: badge)
                            .background(Color.accentColor.opacity(0.12),
                                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        Text(LocalizedStringKey(title))
                            .font(.title2.weight(.bold))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    Text(LocalizedStringKey(message))
                        .font(.body)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let note {
                        Label(note, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.orange)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.orange.opacity(0.1),
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    Spacer(minLength: 0)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Palette.groupedBackground)
            .navigationTitle("Об инструменте")
            #if os(iOS)
            .toolbarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

extension Tool {
    /// Consent note shown for scanning tools that some networks treat as hostile.
    var sensitivityNote: String? {
        isSensitive
            ? "Эта проверка активно опрашивает хосты/сеть. В чужих сетях это может расцениваться как сканирование. Запускайте только там, где у вас есть разрешение."
            : nil
    }
}
