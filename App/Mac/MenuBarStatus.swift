#if os(macOS)
import SwiftUI

/// The menu bar item: the last known state of the hosts the user watches,
/// without bringing the window forward.
///
/// It reads `SharedStore` rather than owning a monitor of its own — monitoring
/// is driven by the app, and this is a read-only window onto its results.
struct MenuBarStatus: View {
    @Environment(\.openWindow) private var openWindow
    @State private var snapshots: [PingSnapshot] = []

    var body: some View {
        Group {
            if snapshots.isEmpty {
                Text("Пока нет результатов")
            } else {
                ForEach(snapshots, id: \.host) { snapshot in
                    Text(label(for: snapshot))
                }
                Divider()
            }
            Button("Открыть CheckNet") {
                openWindow(id: MacWindow.main)
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut("o")
        }
        .onAppear(perform: reload)
        // The menu is rebuilt each time it opens, but a stale list while it is
        // already on screen would be misleading, so it refreshes on a timer too.
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
            reload()
        }
    }

    private func reload() {
        snapshots = SharedStore.snapshots()
    }

    private func label(for snapshot: PingSnapshot) -> String {
        let latency = snapshot.latencyMillis.map { String(format: "%.0f мс", $0) } ?? "нет ответа"
        return "\(snapshot.host) — \(latency)"
    }
}

/// Icon for the menu bar, reflecting the worst status among watched hosts:
/// a filled dot when everything answers, a slash when something is down.
struct MenuBarIcon: View {
    @State private var status: PingSnapshot.Status = .unknown

    var body: some View {
        Image(systemName: symbol)
            .onAppear(perform: reload)
            .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
                reload()
            }
    }

    private var symbol: String {
        switch status {
        case .ok: "checkmark.circle"
        case .degraded: "exclamationmark.circle"
        case .down: "xmark.circle"
        case .unknown: "circle.dotted"
        }
    }

    private func reload() {
        let all = SharedStore.snapshots()
        // Worst wins: one host down matters more than three that are fine.
        if all.contains(where: { $0.status == .down }) { status = .down }
        else if all.contains(where: { $0.status == .degraded }) { status = .degraded }
        else if all.contains(where: { $0.status == .ok }) { status = .ok }
        else { status = .unknown }
    }
}
#endif
