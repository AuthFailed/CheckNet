import WidgetKit
import SwiftUI
import AppIntents

/// User-added controls for Control Center, the Lock Screen and the Action
/// button. Both open the app rather than running in the extension: a network
/// check's whole point is the result, which belongs on screen, and it keeps the
/// engines (and their timeouts) in the full app process instead of an
/// extension's tight budget. Nothing here is published to the Home Screen — the
/// user adds these deliberately, per the product rule.

/// Re-runs the last ping and shows its result at a glance.
struct PingControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: "com.chrsnv.checknet.control.ping",
            provider: LastPingProvider()
        ) { value in
            ControlWidgetButton(action: value.openIntent) {
                Label(value.title, systemImage: "dot.radiowaves.left.and.right")
                Text(value.subtitle)
            }
        }
        .displayName("Пинг хоста")
        .description("Повторяет последнюю проверку задержки.")
    }
}

/// The last stored snapshot, or a neutral placeholder when nothing has run yet.
struct LastPingProvider: ControlValueProvider {
    struct Value {
        var host: String
        var title: String
        var subtitle: String

        var openIntent: OpenURLIntent {
            let url = ControlDeepLink.toolURL("ping", host: host.isEmpty ? nil : host, run: true)
                ?? URL(string: "checknet://tool/ping")!
            return OpenURLIntent(url)
        }
    }

    var previewValue: Value {
        Value(host: "1.1.1.1", title: "1.1.1.1", subtitle: "12 мс")
    }

    func currentValue() async throws -> Value {
        guard let snapshot = SharedStore.latestSnapshot() else {
            return Value(host: "", title: "Пинг", subtitle: "Нет данных")
        }
        return Value(
            host: snapshot.host,
            title: snapshot.host,
            subtitle: ControlSnapshotDisplay.subtitle(snapshot)
        )
    }
}

/// Opens the Блокировки tab to check what the current network restricts.
struct BlockingControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.chrsnv.checknet.control.blocking") {
            ControlWidgetButton(action: OpenURLIntent(
                ControlDeepLink.tabURL("blocking") ?? URL(string: "checknet://tab/blocking")!
            )) {
                Label("Блокировки", systemImage: "hand.raised")
            }
        }
        .displayName("Проверить блокировки")
        .description("Открывает проверки сетевых ограничений.")
    }
}
