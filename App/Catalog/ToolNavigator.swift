import SwiftUI

/// A runtime request to open a tool — set from outside the catalog (Spotlight,
/// a future URL/handoff) and consumed by `CatalogView`, which pushes it onto
/// whichever column model the current layout uses.
@MainActor
@Observable
final class ToolNavigator {
    var pending: ToolRoute?

    func open(_ tool: Tool, autostart: Bool = false) {
        pending = ToolRoute(tool: tool, autostart: autostart)
    }
}
