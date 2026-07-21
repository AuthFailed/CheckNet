import SwiftUI

/// A polished placeholder for tools whose engine is not yet wired to a screen.
struct PlaceholderToolView: View {
    let tool: Tool

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: tool.systemImage)
                    .font(.system(size: 46, weight: .regular))
                    .foregroundStyle(.tint)
                    .padding(.top, 40)
                Text(tool.title)
                    .font(.title2.weight(.bold))
                Text(tool.subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Label("Скоро в этой сборке", systemImage: "hammer")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.quaternary, in: Capsule())
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
        }
        .navigationTitle(tool.title)
        #if os(iOS)
        .toolbarTitleDisplayMode(.inline)
        #endif
    }
}
