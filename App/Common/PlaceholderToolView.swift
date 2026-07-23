import SwiftUI

/// Shown for a tool without a working screen. It answers the question the old
/// "Скоро в этой сборке" chip left open: is this coming, or will it never be
/// here? A tool held back by iOS restrictions says so plainly, with a different
/// icon from one that is merely unbuilt.
struct PlaceholderToolView: View {
    let tool: Tool
    // The hero glyph keeps its weight against the title as text grows.
    @ScaledMetric(relativeTo: .largeTitle) private var glyph: CGFloat = 46

    private var unavailable: Tool.Unavailable {
        tool.unavailable ?? .inDevelopment(tool.info)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: tool.systemImage)
                    .font(.system(size: glyph, weight: .regular))
                    .foregroundStyle(.tint)
                    .padding(.top, 40)
                    .accessibilityHidden(true)
                Text(LocalizedStringKey(tool.title))
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(LocalizedStringKey(tool.subtitle))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Label(unavailable.headline, systemImage: unavailable.icon)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.quaternary, in: Capsule())
                    .padding(.top, 8)

                // The reason, not a vague "soon". For a platform limit this is
                // the whole point of the screen.
                Text(LocalizedStringKey(unavailable.detail))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
        }
        .navigationTitle(LocalizedStringKey(tool.title))
        #if os(iOS)
        .toolbarTitleDisplayMode(.inline)
        #endif
    }
}
