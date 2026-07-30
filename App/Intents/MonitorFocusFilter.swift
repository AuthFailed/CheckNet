import AppIntents

/// A Focus filter: while a chosen Focus (Sleep, Work…) is active, mute the
/// host-down / recovery alerts from network monitoring.
///
/// The system calls `perform()` with the user's per-Focus configuration when
/// that Focus becomes active, so the current choice is persisted where the
/// notifier — foreground and background — reads it. (iOS/macOS resume the app's
/// default state when no Focus is active; a lingering mute is cleared the next
/// time any configured Focus toggles.)
struct MonitorFocusFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Network monitoring"
    static let description = IntentDescription(
        "Mutes down/recovery alerts for monitored hosts in the chosen Focus."
    )

    @Parameter(title: "Mute monitoring alerts", default: true)
    var muteHostAlerts: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: muteHostAlerts
                ? "Monitoring alerts muted"
                : "Monitoring alerts on"
        )
    }

    func perform() async throws -> some IntentResult {
        FocusMonitorState.setMuted(muteHostAlerts)
        return .result()
    }
}
