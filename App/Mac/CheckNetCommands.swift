#if os(macOS)
import SwiftUI

/// Menu bar commands and their keyboard shortcuts.
///
/// The app had no `.commands` at all, so the Mac build shipped with the default
/// File/Edit menus and not one shortcut. These are routed through
/// `ToolCommandBus` because the menu lives outside the view hierarchy that owns
/// the running check.
struct CheckNetCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Новая проверка") { ToolCommandBus.shared.send(.newCheck) }
                .keyboardShortcut("n")
        }

        CommandMenu("Проверка") {
            Button("Запустить проверку") { ToolCommandBus.shared.send(.run) }
                .keyboardShortcut("r")
            Button("Остановить") { ToolCommandBus.shared.send(.stop) }
                .keyboardShortcut(".", modifiers: .command)
            Divider()
            Button("Поиск") { ToolCommandBus.shared.send(.search) }
                .keyboardShortcut("f")
        }
    }
}

/// A tiny broadcast channel from the menu bar to whichever screen is on top.
///
/// Menu commands are built once, outside any view, so they cannot reach a
/// specific tool's model directly. Screens observe this and act only when they
/// are the ones on screen.
@Observable
@MainActor
final class ToolCommandBus {
    static let shared = ToolCommandBus()

    enum Command: Equatable { case run, stop, search, newCheck }

    /// Incremented with every command so observers see a change even when the
    /// same command is sent twice in a row.
    private(set) var latest: (command: Command, id: Int)?
    private var counter = 0

    func send(_ command: Command) {
        counter += 1
        latest = (command, counter)
    }
}
#endif
