#if os(iOS)
import AppIntents

/// The "Стоп" button on the ping Live Activity. A `LiveActivityIntent` runs in
/// the app's process, so it just raises the shared stop signal; the running
/// ping loop sees it on its next tick and finishes the run (which ends the
/// activity). Lives in `Shared/` so both the app and the widget extension —
/// where the button is rendered — can reference it.
struct StopPingLiveActivityIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Остановить проверку"
    static let description = IntentDescription("Останавливает текущую проверку задержки.")

    func perform() async throws -> some IntentResult {
        LiveActivitySignal.requestStop()
        return .result()
    }
}
#endif
