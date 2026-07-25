import Foundation
import CryptoKit

/// Encoder/decoder for `incy://crypt1/<payload>` deep links — the form the INCY
/// clients import a subscription from. AES-256-GCM over a compact JSON
/// `{"n":name,"url":url,"v":1}`; `payload = base64url(nonce ‖ ciphertext ‖ tag)`.
///
/// This is obfuscation, not secrecy: the key `K1` is derived from constants and
/// key material that ship inside every INCY client (and the open-source
/// `INCY-DEV/incy-link-encoder`), so anyone can reconstruct it. We derive the
/// same `K1` and check it against the published fingerprint. Purpose: let an
/// operator hand out a link + QR instead of a bare subscription URL.
public enum IncyLink {
    public static let scheme = "incy://crypt1/"

    public enum LinkError: Error, Equatable, Sendable {
        case notAnIncyLink
        case invalidPayload
        case authenticationFailed
        case badJSON
        case emptyURL
    }

    public struct Decoded: Equatable, Sendable {
        public let url: String
        public let name: String?
    }

    // MARK: - Public API

    /// Build an `incy://crypt1/…` link from a subscription URL (+ optional name).
    /// A fresh random nonce is used each call.
    public static func encode(url: String, name: String? = nil) throws -> String {
        try encode(url: url, name: name, nonce: AES.GCM.Nonce())
    }

    /// Decode an `incy://crypt1/…` link back to its URL (+ optional name).
    public static func decode(_ link: String) throws -> Decoded {
        let s = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.hasPrefix(scheme) else { throw LinkError.notAnIncyLink }
        guard let wire = base64URLDecode(String(s.dropFirst(scheme.count))),
              wire.count >= 12 + 16 else { throw LinkError.invalidPayload }

        let nonce = wire.prefix(12)
        let tag = wire.suffix(16)
        let ct = wire.subdata(in: 12 ..< (wire.count - 16))
        let plain: Data
        do {
            let box = try AES.GCM.SealedBox(nonce: try AES.GCM.Nonce(data: nonce),
                                            ciphertext: ct, tag: tag)
            plain = try AES.GCM.open(box, using: key)
        } catch {
            throw LinkError.authenticationFailed
        }
        guard let obj = try? JSONSerialization.jsonObject(with: plain) as? [String: Any],
              let url = obj["url"] as? String, !url.isEmpty else { throw LinkError.badJSON }
        let name = obj["n"] as? String
        return Decoded(url: url, name: (name?.isEmpty == false) ? name : nil)
    }

    // MARK: - Internal (deterministic for tests)

    static func encode(url: String, name: String?, nonce: AES.GCM.Nonce) throws -> String {
        guard !url.isEmpty else { throw LinkError.emptyURL }
        var payload: [String: Any] = ["url": url, "v": 1]
        if let name, !name.isEmpty { payload["n"] = String(name.prefix(128)) }
        // sorted + compact + unescaped slashes → same wire shape as the reference
        // encoder (keys sorted: n, url, v).
        let data = try JSONSerialization.data(withJSONObject: payload,
                                              options: [.sortedKeys, .withoutEscapingSlashes])
        let sealed = try AES.GCM.seal(data, using: key, nonce: nonce)
        var wire = Data(sealed.nonce)
        wire.append(sealed.ciphertext)
        wire.append(sealed.tag)
        return scheme + base64URLEncode(wire)
    }

    // MARK: - Key derivation

    /// Public key material lifted from `incy-link-encoder` (32 bytes each, from
    /// the two shipped 4 KiB asset blobs at fixed offsets). Not a secret.
    private static let keymatA = "7odqBjr3BNe0CfGRDZcxzBQZCB7AiZOgEnBVaHPh7y0="
    private static let keymatB = "z1EN9DsquX6phHju5fGxz4DjpIT8k2kxbM2H5Ut5l7c="

    /// SHA-256 of `K1` — sanity check that our derivation matches the clients.
    public static let keyFingerprint =
        "b6bf708471cc90043232967660aade86a50b4e57929db2e53c5fa34db624c08c"

    static let key: SymmetricKey = {
        var seed = Data()
        for part in ["incy", "deep", "crypt1", "v2026.06"] { seed.append(Data(part.utf8)) }
        seed.append(Data(base64Encoded: keymatA) ?? Data())
        seed.append(Data(base64Encoded: keymatB) ?? Data())
        return SymmetricKey(data: Data(SHA256.hash(data: seed)))
    }()

    /// Hex SHA-256 of the derived key — compared against `keyFingerprint`.
    static var derivedFingerprint: String {
        let digest = key.withUnsafeBytes { SHA256.hash(data: Data($0)) }
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - base64url

    private static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func base64URLDecode(_ text: String) -> Data? {
        var s = text.filter { !$0.isWhitespace }
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while s.hasSuffix("=") { s.removeLast() }
        let pad = (4 - s.count % 4) % 4
        s += String(repeating: "=", count: pad)
        return Data(base64Encoded: s)
    }
}
