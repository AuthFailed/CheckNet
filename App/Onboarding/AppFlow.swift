import SwiftUI

/// First-run and permission flow state, persisted across launches.
///
/// Three things live here: whether onboarding has been shown, which version's
/// "What's New" the user has already seen, and whether the local-network
/// permission has been asked for (and refused). Keeping them in one observed
/// object means the window, the catalog and the tool screens all read the same
/// truth instead of each poking `UserDefaults` on its own.
@MainActor
@Observable
final class AppFlow {
    var onboardingDone: Bool {
        didSet { UserDefaults.standard.set(onboardingDone, forKey: Keys.onboarding) }
    }
    /// The last version whose notes were dismissed. Compared against
    /// `WhatsNew.version` to decide whether to show them again.
    var lastWhatsNewSeen: String {
        didSet { UserDefaults.standard.set(lastWhatsNewSeen, forKey: Keys.whatsNew) }
    }
    /// Whether the local-network prompt has been surfaced at least once. Once it
    /// has, we do not put the pre-permission screen in the way again — the user
    /// answered, and the answer lives in iOS Settings from then on.
    var localNetworkAsked: Bool {
        didSet { UserDefaults.standard.set(localNetworkAsked, forKey: Keys.localNetAsked) }
    }
    /// Set when the system prompt came back denied. Drives the catalog banner
    /// that points the user at Settings; not persisted, because the moment they
    /// grant access in Settings and return, it should clear on the next check.
    var localNetworkDenied = false

    var shouldShowWhatsNew: Bool {
        onboardingDone && lastWhatsNewSeen != WhatsNew.version
    }

    init() {
        let d = UserDefaults.standard
        // UI tests drive the catalog directly and must not fight the first-run
        // onboarding that would otherwise cover it. The flag is in-memory only,
        // so a real launch is unaffected.
        let uiTest = ProcessInfo.processInfo.arguments.contains("-skipOnboarding")
        onboardingDone = uiTest || d.bool(forKey: Keys.onboarding)
        lastWhatsNewSeen = uiTest ? WhatsNew.version : (d.string(forKey: Keys.whatsNew) ?? "")
        localNetworkAsked = uiTest || d.bool(forKey: Keys.localNetAsked)
    }

    /// Finish onboarding. A brand-new user is also marked as having seen this
    /// version's notes, so "What's New" does not appear on top of a first run —
    /// it is for people coming from an earlier version.
    func completeOnboarding() {
        onboardingDone = true
        lastWhatsNewSeen = WhatsNew.version
    }

    func markWhatsNewSeen() {
        lastWhatsNewSeen = WhatsNew.version
    }

    private enum Keys {
        static let onboarding = "checknet.onboardingDone"
        static let whatsNew = "checknet.whatsNewSeen"
        static let localNetAsked = "checknet.localNetworkAsked"
    }
}

extension Tool {
    /// Tools that reach into the local network and so need the iOS Local Network
    /// permission before they can work: the device browser, the range scanner
    /// and the Bonjour browser.
    var needsLocalNetwork: Bool {
        switch self {
        case .networkBrowser, .ipScanner, .bonjour: true
        default: false
        }
    }
}
