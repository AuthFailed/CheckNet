import Foundation
import Network

/// Proactively triggers the iOS "Local Network" privacy prompt.
///
/// iOS silently drops local-network traffic — and, in practice, ICMP sockets —
/// until the user grants access. The simulator does not enforce this, so it must
/// be handled explicitly for real devices. Starting a Bonjour listener + browser
/// is the Apple-sanctioned way to surface the prompt and learn the result.
final class LocalNetworkPermission: @unchecked Sendable {
    static let shared = LocalNetworkPermission()

    private let queue = DispatchQueue(label: "checknet.localnet.permission")
    private var browser: NWBrowser?
    private var listener: NWListener?
    private var completion: (@Sendable (Bool) -> Void)?
    private var finished = false

    /// Requests the permission (idempotent per launch). `granted` is best-effort.
    func request(_ completion: (@Sendable (Bool) -> Void)? = nil) {
        #if os(iOS)
        queue.async { [self] in
            guard listener == nil, browser == nil else { completion?(false); return }
            self.completion = completion
            self.finished = false
            startListener()
            startBrowser()
        }
        #else
        completion?(true)
        #endif
    }

    private func startListener() {
        do {
            let listener = try NWListener(using: .tcp)
            listener.service = NWListener.Service(name: "CheckNet", type: "_checknet._tcp")
            listener.newConnectionHandler = { $0.cancel() }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            // Ignore; the browser alone still triggers the prompt in most cases.
        }
    }

    private func startBrowser() {
        let params = NWParameters()
        params.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: "_checknet._tcp", domain: nil), using: params)
        browser.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready, .failed:
                self?.settle(granted: state == .ready)
            case .waiting:
                // "waiting" typically means the prompt was denied or is pending.
                break
            default:
                break
            }
        }
        browser.browseResultsChangedHandler = { [weak self] _, _ in
            self?.settle(granted: true)
        }
        browser.start(queue: queue)
        self.browser = browser
        // Safety timeout so we always resolve.
        queue.asyncAfter(deadline: .now() + 6) { [weak self] in self?.settle(granted: true) }
    }

    private func settle(granted: Bool) {
        guard !finished else { return }
        finished = true
        let done = completion
        completion = nil
        browser?.cancel(); browser = nil
        listener?.cancel(); listener = nil
        DispatchQueue.main.async { done?(granted) }
    }
}
