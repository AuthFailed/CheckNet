#if os(iOS)
import AppIntents

/// The "Stop" button on the ping Live Activity. A `LiveActivityIntent` runs in
/// the app's process, so it just raises the shared stop signal; the running
/// ping loop sees it on its next tick and finishes the run (which ends the
/// activity). Lives in `Shared/` so both the app and the widget extension —
/// where the button is rendered — can reference it.
struct StopPingLiveActivityIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop the test"
    static let description = IntentDescription("Stops the current latency test.")

    func perform() async throws -> some IntentResult {
        LiveActivitySignal.requestStop()
        return .result()
    }
}
#endif
