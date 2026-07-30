import SwiftUI

/// Placeholder for a VPN tool that isn't built yet — the "in development" version
/// of the same scaffold the Tests tab uses, so an unimplemented tool never
/// shows a half-working screen.
struct VPNPlaceholderView: View {
    let tool: VPNTool
    @ScaledMetric(relativeTo: .largeTitle) private var glyph: CGFloat = 46

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

                Label("В разработке", systemImage: "hammer")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.quaternary, in: Capsule())
                    .padding(.top, 8)

                Text(LocalizedStringKey(tool.info))
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
