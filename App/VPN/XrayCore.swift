import Foundation
#if canImport(LibXray)
import LibXray
#endif

/// Thin bridge over the bundled Xray core (libXray). The core exposes a single
/// C entrypoint — `CGoInvoke(requestJSON) -> responseJSON` — which we wrap in
/// typed calls. This is what lets the "Xray inbound availability" tool run a
/// real handshake in-process on iOS, where a downloaded binary can't be exec'd.
enum XrayCore {
    struct CoreError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Whether the core is linked into this build.
    static var isAvailable: Bool {
        #if canImport(LibXray)
        true
        #else
        false
        #endif
    }

    /// Sends `{apiVersion, method, payload}` and returns the `data` value on
    /// success, or throws with the core's `error` string.
    @discardableResult
    static func invoke(_ method: String, payload: [String: Any] = [:]) throws -> Any? {
        #if canImport(LibXray)
        var request: [String: Any] = ["apiVersion": 1, "method": method]
        if !payload.isEmpty { request["payload"] = payload }
        let reqData = try JSONSerialization.data(withJSONObject: request)
        guard let cReq = strdup(String(decoding: reqData, as: UTF8.self)) else {
            throw CoreError(message: "out of memory")
        }
        defer { free(cReq) }
        guard let cRes = CGoInvoke(cReq) else { throw CoreError(message: "core didn't respond") }
        defer { CGoFree(cRes) }

        let obj = try JSONSerialization.jsonObject(with: Data(String(cString: cRes).utf8))
        guard let dict = obj as? [String: Any] else { throw CoreError(message: "invalid core response") }
        if dict["success"] as? Bool == true { return dict["data"] }
        throw CoreError(message: (dict["error"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "core error")
        #else
        throw CoreError(message: "The Xray core isn't included in this build")
        #endif
    }

    /// Xray version string — needs no server, so it doubles as a "core is live" probe.
    static func version() throws -> String {
        (try invoke("xrayVersion") as? [String: Any])?["version"] as? String ?? "—"
    }

    /// Starts the core with a full config JSON (e.g. a local SOCKS inbound + the
    /// tested outbound). One global instance — call `stop()` first if unsure.
    static func run(configJSON: String) throws {
        _ = try invoke("runXrayFromJson", payload: ["configJSON": configJSON])
    }

    static func stop() {
        _ = try? invoke("stopXray")
    }
}
