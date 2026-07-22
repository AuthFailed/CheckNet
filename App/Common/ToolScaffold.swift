import SwiftUI

enum ToolLayout {
    /// Readable measure for a single column of cards.
    static let contentWidth: CGFloat = 640
    /// Leading column on iPad at full width.
    static let leadingColumnWidth: CGFloat = 360
    /// Leading rail in landscape on a phone — narrower, because there height is
    /// what is scarce, not width.
    static let railWidth: CGFloat = 320
    /// Narrowest a result module may become before the grid drops a column.
    static let moduleMinWidth: CGFloat = 360
    static let spacing: CGFloat = 16
}

/// The shared skeleton of a tool screen, in the three arrangements the design
/// calls for. Which one applies follows the size classes, not the device:
///
/// - **stack** — compact width, regular height (iPhone portrait, iPad Split ½).
///   One column capped at 640 pt, run button pinned in the bottom safe area.
/// - **rail** — compact width, compact height (iPhone landscape). A 320 pt
///   leading rail holds the input *and* the run button, each side scrolls
///   independently, and there is no bottom bar: in landscape a pinned bar eats
///   a fifth of the screen.
/// - **twoColumn** — regular width (iPad at full width, Mac). A 360 pt leading
///   column, results in an adaptive grid beside it.
///
/// `leading` is the input and whatever belongs with it; `content` is the result
/// modules, which flow into columns when there is room. This split is the point:
/// a host field is not a result and must not be laid into the grid next to one.
/// Screens that pass no `leading` keep the plain single column, so screens can
/// migrate one at a time.
struct ToolScaffold<Leading: View, Content: View, Bottom: View>: View {
    enum Mode { case stack, rail, twoColumn }

    var spacing: CGFloat = ToolLayout.spacing
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var content: () -> Content
    @ViewBuilder var bottom: () -> Bottom

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.verticalSizeClass) private var vSize
    #endif

    private var mode: Mode {
        #if os(iOS)
        // Height is asked about first, and deliberately so. A Pro Max in
        // landscape reports *regular* width but compact height, so asking about
        // width first put a phone into the iPad layout: three columns on a
        // 430 pt-tall screen, the last one squeezed until it wrapped one letter
        // per line. Whenever height is compact the rail is the right answer,
        // however wide the device claims to be.
        if vSize == .compact { return .rail }
        return hSize == .regular ? .twoColumn : .stack
        #else
        return .twoColumn
        #endif
    }

    /// A screen that hasn't been split yet keeps the old behaviour rather than
    /// showing an empty leading column.
    private var isSplit: Bool { Leading.self != EmptyView.self }

    var body: some View {
        Group {
            if isSplit, mode != .stack {
                splitLayout
            } else {
                stackLayout
            }
        }
        .background(Palette.groupedBackground)
    }

    // MARK: Stack

    private var stackLayout: some View {
        ScrollView {
            VStack(spacing: spacing) {
                leading()
                content()
            }
            .padding(ToolLayout.spacing)
            .frame(maxWidth: ToolLayout.contentWidth)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) { bottom() }
    }

    // MARK: Rail and two-column

    private var splitLayout: some View {
        HStack(alignment: .top, spacing: 0) {
            ScrollView {
                VStack(spacing: spacing) {
                    leading()
                    // Here the run button travels with the input instead of
                    // being pinned across the bottom.
                    bottom()
                }
                .padding(ToolLayout.spacing)
            }
            .frame(width: mode == .rail ? ToolLayout.railWidth : ToolLayout.leadingColumnWidth)
            .scrollDismissesKeyboard(.interactively)

            Divider()

            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: ToolLayout.moduleMinWidth), spacing: spacing)],
                    alignment: .leading,
                    spacing: spacing
                ) {
                    content()
                }
                .padding(ToolLayout.spacing)
            }
        }
    }
}

// MARK: - Convenience initialisers

extension ToolScaffold where Leading == EmptyView, Bottom == EmptyView {
    /// Results-only screen: no input, no run button.
    init(spacing: CGFloat = ToolLayout.spacing, @ViewBuilder content: @escaping () -> Content) {
        self.init(spacing: spacing, leading: { EmptyView() }, content: content, bottom: { EmptyView() })
    }
}

extension ToolScaffold where Leading == EmptyView {
    /// Not yet split into input and results — behaves exactly as before.
    init(spacing: CGFloat = ToolLayout.spacing,
         @ViewBuilder content: @escaping () -> Content,
         @ViewBuilder bottom: @escaping () -> Bottom) {
        self.init(spacing: spacing, leading: { EmptyView() }, content: content, bottom: bottom)
    }
}

#if os(macOS)
extension View {
    /// Wires the ⌘R / ⌘. menu commands to one screen's run and stop actions.
    ///
    /// Menu commands are built once, outside any view, so they cannot reach a
    /// tool's model directly — they arrive through `ToolCommandBus`.
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
