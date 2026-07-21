import SwiftUI

/// The shared skeleton of a tool screen.
///
/// Every tool repeated the same four things by hand — a `ScrollView` around a
/// `VStack(spacing: 16)` with 16 pt padding, the grouped background, the
/// snappy phase animation, and a `RunButton` pinned via `safeAreaInset`. None
/// of them limited the content width, so on iPad and Mac a card stretched to
/// the full window and a two-word result sat alone on a 1300 pt line.
///
/// The width cap is the readable-width convention: text stops growing past a
/// comfortable measure and the column centres instead. On iPhone the cap never
/// binds (the widest phone is far below it), so no size-class check is needed —
/// the same code is correct on every device.
///
/// Only the container is standardised here. How result cards should *arrange*
/// themselves once there is room for two columns is a visual design question,
/// deliberately left out of this type until it has been designed.
enum ToolLayout {
    /// Roughly the width at which a line of text stops being comfortable to
    /// read. Cards and the run button share it, so a screen reads the same on
    /// iPad as on iPhone instead of stretching to the window.
    static let contentWidth: CGFloat = 640
}

struct ToolScaffold<Content: View, Bottom: View>: View {
    var spacing: CGFloat = 16
    @ViewBuilder var content: () -> Content
    @ViewBuilder var bottom: () -> Bottom

    var body: some View {
        ScrollView {
            VStack(spacing: spacing) {
                content()
            }
            .padding(16)
            .frame(maxWidth: ToolLayout.contentWidth)
            // The inner frame caps the width, this one centres that column in
            // whatever space is left.
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Palette.groupedBackground)
        .safeAreaInset(edge: .bottom) {
            bottom()
        }
    }
}

extension ToolScaffold where Bottom == EmptyView {
    /// A tool screen with no pinned run button (results-only screens such as
    /// the interface list).
    init(spacing: CGFloat = 16, @ViewBuilder content: @escaping () -> Content) {
        self.init(spacing: spacing, content: content, bottom: { EmptyView() })
    }
}

#if os(macOS)
extension View {
    /// Wires the ⌘R / ⌘. menu commands to one screen's run and stop actions.
    ///
    /// Menu commands are built once, outside any view, so they cannot reach a
    /// tool's model directly — they arrive through `ToolCommandBus`. Applying
    /// this in `ToolScaffold`'s users means the shortcut works on every tool
    /// rather than only the one screen that happened to observe the bus.
    func toolCommands(isRunning: Bool, run: @escaping () -> Void, stop: @escaping () -> Void) -> some View {
        onChange(of: ToolCommandBus.shared.latest?.id) { _, _ in
            switch ToolCommandBus.shared.latest?.command {
            case .run: if !isRunning { run() }
            case .stop: if isRunning { stop() }
            default: break
            }
        }
    }
}
#else
extension View {
    /// No menu bar on iOS; the shortcuts do not exist there.
    func toolCommands(isRunning: Bool, run: @escaping () -> Void, stop: @escaping () -> Void) -> some View { self }
}
#endif

extension View {
    /// Inline navigation title on iOS; on macOS there is no navigation bar and
    /// the modifier does not apply.
    func toolTitleDisplayMode() -> some View {
        #if os(iOS)
        toolbarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}
