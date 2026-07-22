import SwiftUI

/// Tactile feedback for the moments a diagnostic app has: a check that ends
/// while the phone is face down on the desk, and the small confirmations that
/// otherwise leave no trace (pinning a tool, saving a host, copying a value).
///
/// Built on `.sensoryFeedback`, so the system's own accessibility and
/// Silent-mode rules apply, and nothing plays on a Mac. The one thing added on
/// top is the app's own switch, because a network tool is often run in places
/// where a buzzing phone is unwelcome.
enum Haptic {
    /// A check that produced a result.
    case success
    /// A check that could not run, or a host that went down.
    case failure
    /// A result that is not an error but wants attention: a block detected, a
    /// port found open.
    case warning
    /// A small confirmation — pin, save, copy.
    case light

    #if os(iOS)
    var feedback: SensoryFeedback {
        switch self {
        case .success: return .success
        case .failure: return .error
        case .warning: return .warning
        case .light: return .impact(weight: .light)
        }
    }
    #endif
}

extension View {
    /// Plays `haptic` whenever `trigger` changes, unless the user turned
    /// feedback off.
    ///
    /// The settings check lives here rather than at each call site so that
    /// adding feedback to a screen stays a one-line change.
    func haptic<T: Equatable>(_ haptic: Haptic, trigger: T) -> some View {
        modifier(HapticModifier(haptic: haptic, trigger: trigger))
    }

    /// Plays feedback only when `condition` holds for the new value — for a
    /// phase that can end in either success or failure.
    func haptic<T: Equatable>(_ haptic: Haptic, trigger: T, condition: @escaping (T) -> Bool) -> some View {
        modifier(HapticModifier(haptic: haptic, trigger: trigger, condition: condition))
    }
}

private struct HapticModifier<T: Equatable>: ViewModifier {
    let haptic: Haptic
    let trigger: T
    var condition: ((T) -> Bool)?

    @Environment(AppSettings.self) private var settings

    func body(content: Content) -> some View {
        #if os(iOS)
        content.sensoryFeedback(haptic.feedback, trigger: trigger) { _, new in
            guard settings.hapticsEnabled else { return false }
            return condition?(new) ?? true
        }
        #else
        // No Taptic Engine on a Mac, and `.sensoryFeedback` is a no-op there.
        content
        #endif
    }
}
