import Foundation
import UserNotifications

/// Owns the app's local-notification surface for host monitoring: authorization,
/// the actionable category, foreground presentation and posting.
///
/// A single shared instance is the `UNUserNotificationCenter` delegate, so both
/// the foreground `MonitoringManager` and the background refresh route through
/// one place. Posting is `nonisolated` because the background task runs off the
/// main actor — `UNUserNotificationCenter` is itself thread-safe.
@MainActor
final class HostNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = HostNotifier()

    /// Set by the app so a tapped action can route to a screen or re-check.
    var onAction: ((_ actionID: String, _ host: String) -> Void)?

    private override init() { super.init() }

    /// Registers the delegate and the actionable category. Safe to call twice.
    func configure() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let open = UNNotificationAction(
            identifier: MonitorNotification.actionOpen,
            title: "Открыть", options: [.foreground])
        let recheck = UNNotificationAction(
            identifier: MonitorNotification.actionRecheck,
            title: "Проверить снова", options: [])
        let category = UNNotificationCategory(
            identifier: MonitorNotification.categoryID,
            actions: [open, recheck], intentIdentifiers: [], options: [])
        center.setNotificationCategories([category])
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Builds and posts a notification for a monitor transition. `nonisolated`
    /// so the background task can call it directly.
    nonisolated static func post(_ plan: MonitorNotification.Plan, host: String) {
        // A Focus filter (see MonitorFocusFilter) can silence monitor alerts.
        guard !FocusMonitorState.isMuted() else { return }
        let content = UNMutableNotificationContent()
        content.title = plan.title
        content.body = plan.body
        content.sound = .default
        content.categoryIdentifier = MonitorNotification.categoryID
        content.threadIdentifier = plan.threadID
        content.userInfo = [MonitorNotification.hostKey: host]
        #if os(iOS)
        content.interruptionLevel = plan.timeSensitive ? .timeSensitive : .active
        #endif
        let request = UNNotificationRequest(
            identifier: "monitor.\(host).\(plan.timeSensitive ? "down" : "up")",
            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: UNUserNotificationCenterDelegate

    /// Show monitor alerts even while the app is in the foreground — a silent
    /// drop would hide exactly the event the user is watching for.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let host = response.notification.request.content.userInfo[MonitorNotification.hostKey] as? String ?? ""
        // A plain tap on the banner counts as "open".
        let actionID = response.actionIdentifier == UNNotificationDefaultActionIdentifier
            ? MonitorNotification.actionOpen
            : response.actionIdentifier
        onAction?(actionID, host)
    }
}
