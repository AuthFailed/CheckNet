import SwiftUI

/// What a tool screen shows before it has been run.
///
/// The area under the input used to be simply blank, which says nothing about
/// what the button will do or what a sensible input looks like. Ping was the
/// only screen that explained itself; this is that hint, generalised, with one
/// addition: the example is tappable, so a user who does not have a host in
/// mind can still see the tool work.
///
/// Text arrives as `LocalizedStringKey` rather than `String` so the compiler
/// extracts it into the string catalog. A `String` here would look identical
/// and stay Russian in every other language.
struct ToolIdleHint: View {
    let icon: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    /// A host, domain or range that makes sense for this tool. Tapping it fills
    /// the input rather than running anything — the run stays the user's call.
    var example: String?
    /// What the input holds right now. The offer is hidden when it already
    /// holds the example, where the button would do nothing visible.
    var current: String = ""
    var useExample: (() -> Void)?

    // The user's real Dynamic Type setting, read before this view caps its own
    // text below — so it still reflects when the reader is at an accessibility
    // size even though the hint itself stops growing there.
    @Environment(\.dynamicTypeSize) private var typeSize

    private var showsExample: Bool {
        guard let example, useExample != nil else { return false }
        return current.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(example) != .orderedSame
    }

    var body: some View {
        VStack(spacing: 10) {
            // Decorative only. At accessibility sizes the vertical budget is
            // spent on the title and message instead, so the glyph steps aside
            // rather than pushing the last line of the message under the run
            // button.
            if !typeSize.isAccessibilitySize {
                Image(systemName: icon)
                    // Scales with Dynamic Type instead of sitting at a fixed 40 pt.
                    .font(.system(.largeTitle))
                    .foregroundStyle(.tint)
            }

            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

            if showsExample, let example, let useExample {
                Button {
                    useExample()
                } label: {
                    Label {
                        Text("Подставить \(example)")
                    } icon: {
                        Image(systemName: "arrow.turn.down.left")
                    }
                    .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        // Only a small breather from the card above: the scaffold already spaces
        // the leading section and this block apart, and a large fixed inset here
        // pushed the hint under the pinned run button at accessibility type sizes.
        .padding(.top, 12)
        // This is supplementary orientation text, not a result. Past the first
        // accessibility step it would grow until the run button clipped it mid
        // sentence — the tool still works, so a hint you can't read is the worse
        // outcome. Cap its growth here so it stays large but whole; the input and
        // the results keep scaling to the user's full setting.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        // One announcement rather than three fragments; the example stays a
        // separate control.
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    ToolIdleHint(
        icon: "point.topleft.down.to.point.bottomright.curvepath",
        title: "Готово к трассировке",
        message: "Покажем каждый маршрутизатор на пути до хоста и задержку на каждом шаге.",
        example: "cloudflare.com",
        current: "",
        useExample: {}
    )
}
