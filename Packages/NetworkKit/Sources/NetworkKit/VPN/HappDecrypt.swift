import Foundation
import Security
import CryptoKit

/// Decryptor for `happ://crypt…` deep links — the encrypted form of a Happ
/// subscription/config link. Everything runs on-device.
///
/// Schemes:
///   * `crypt` / `crypt2` / `crypt3` / `crypt4` — base64 → RSA PKCS#1 v1.5,
///     decrypted block-by-block by key size (a long link spans several blocks).
///   * `crypt5` — byte shuffles recover a marker + body; the marker picks one of
///     the bundled RSA keys that unwraps a ChaCha20 key; ChaCha20-Poly1305 then
///     decrypts the payload. Both the legacy and salted/XOR layouts are handled.
///
/// The RSA key material is public (it ships inside every Happ client and the
/// open-source `LeeeeT/happ-decryptor` / `amurcanov/happ-decrypt-universal`
/// tools); we bundle the same set. crypt5 variants that only the vendor's CPU
/// emulator handles are reported as unsupported rather than mis-decrypted.
public enum HappDecrypt {
    public enum DecryptError: Error, Equatable, Sendable {
        case notACryptLink
        case keysUnavailable
        case unknownMarker
        case rsaFailed
        case badFormat
        case authenticationFailed
    }

    private static let prefixes: [(String, Int)] = [
        ("happ://crypt5/", 4),
        ("happ://crypt4/", 3),
        ("happ://crypt3/", 2),
        ("happ://crypt2/", 1),
        ("happ://crypt/", 0),
    ]
    private static let modeNames = ["crypt", "crypt2", "crypt3", "crypt4", "crypt5"]

    /// Mode + name preview without touching the keys — for a UI hint.
    public struct Preview: Equatable, Sendable {
        public let mode: Int
        public let name: String
        public let payloadLength: Int
    }

    public static func inspect(_ link: String) -> Preview? {
        guard let (mode, body) = parse(link) else { return nil }
        return Preview(mode: mode, name: modeNames[mode], payloadLength: body.count)
    }

    /// Decrypt a `happ://crypt…` link to its plaintext (usually a subscription
    /// URL or config).
    public static func decrypt(_ link: String) throws -> String {
        guard let (mode, body) = parse(link) else { throw DecryptError.notACryptLink }
        let store = HappKeyStore.shared
        guard !store.native.isEmpty, !store.crypt5.isEmpty else { throw DecryptError.keysUnavailable }

        if mode == 4 { return try decryptCrypt5(body, store: store) }
        guard mode < store.native.count else { throw DecryptError.badFormat }
        return try decryptClassic(body, key: store.native[mode])
    }

    // MARK: - crypt1…4

    private static func decryptClassic(_ body: String, key: SecKey) throws -> String {
        guard let cipher = base64Decode(body) else { throw DecryptError.badFormat }
        let block = SecKeyGetBlockSize(key)
        guard block > 0, cipher.count % block == 0, !cipher.isEmpty else { throw DecryptError.badFormat }
        var out = Data()
        var i = 0
        while i < cipher.count {
            out.append(try rsaDecrypt(key, cipher.subdata(in: i ..< i + block)))
            i += block
        }
        guard let text = String(data: out, encoding: .utf8) else { throw DecryptError.badFormat }
        return text
    }

    // MARK: - crypt5

    private static func decryptCrypt5(_ payload: String, store: HappKeyStore) throws -> String {
        let shuffled = swapBlockHalves(Array(payload.utf8))
        guard shuffled.count >= 8 else { throw DecryptError.badFormat }
        let marker = latin(Array(shuffled[0..<4]) + Array(shuffled[(shuffled.count - 4)...]))
        guard let key = store.crypt5[marker] else { throw DecryptError.unknownMarker }
        let body = Array(shuffled[4 ..< shuffled.count - 4])

        let preferSalted = body.count > 12 && !(body[12] >= 48 && body[12] <= 57)
        var firstError: Error?
        for salted in [preferSalted, !preferSalted] {
            do { return try decryptCrypt5Body(body, key: key, salted: salted) }
            catch { if firstError == nil { firstError = error } }
        }
        throw firstError ?? DecryptError.badFormat
    }

    private static func decryptCrypt5Body(_ body: [UInt8], key: SecKey, salted: Bool) throws -> String {
        guard body.count >= 13 else { throw DecryptError.badFormat }
        let nonce = Array(body[0..<12])
        var salt: [UInt8]?
        var lengthStart = 12
        if salted {
            guard body.count >= 22 else { throw DecryptError.badFormat }
            salt = Array(body[14..<22])
            lengthStart = 22
        }
        var lengthEnd = lengthStart
        while lengthEnd < body.count, body[lengthEnd] >= 48, body[lengthEnd] <= 57 { lengthEnd += 1 }
        guard lengthEnd > lengthStart,
              let segmentLength = Int(latin(Array(body[lengthStart..<lengthEnd]))) else {
            throw DecryptError.badFormat
        }
        let packed = Array(body[lengthEnd...])
        guard !packed.isEmpty, segmentLength >= 0, segmentLength <= packed.count - 1 else {
            throw DecryptError.badFormat
        }

        let encryptedURL = latin(Array(packed[1 ..< 1 + segmentLength]))
        guard let rsaCipher = base64Decode(latin(Array(packed[(1 + segmentLength)...]))) else {
            throw DecryptError.badFormat
        }
        let rsaPlain = try rsaDecrypt(key, rsaCipher)
        guard let keyMaterial = base64Decode(latin(swapAdjacent(Array(rsaPlain)))),
              keyMaterial.count == 32 else { throw DecryptError.badFormat }

        var chachaKey = Array(keyMaterial)
        if let salt { for i in chachaKey.indices { chachaKey[i] ^= salt[i % salt.count] } }

        guard let sealed = base64Decode(encryptedURL), sealed.count >= 16 else { throw DecryptError.badFormat }
        let intermediate = try chachaOpen(key: chachaKey, nonce: nonce, sealed: Array(sealed))
        guard let plain = base64Decode(latin(swapAdjacent(intermediate))),
              let text = String(data: plain, encoding: .utf8) else { throw DecryptError.badFormat }
        return text
    }

    private static func chachaOpen(key: [UInt8], nonce: [UInt8], sealed: [UInt8]) throws -> [UInt8] {
        do {
            let symKey = SymmetricKey(data: Data(key))
            let nonceObj = try ChaChaPoly.Nonce(data: Data(nonce))
            let ct = Data(sealed[0 ..< sealed.count - 16])
            let tag = Data(sealed[(sealed.count - 16)...])
            let box = try ChaChaPoly.SealedBox(nonce: nonceObj, ciphertext: ct, tag: tag)
            return Array(try ChaChaPoly.open(box, using: symKey))
        } catch {
            throw DecryptError.authenticationFailed
        }
    }

    // MARK: - RSA (Security)

    private static func rsaDecrypt(_ key: SecKey, _ cipher: Data) throws -> Data {
        var error: Unmanaged<CFError>?
        guard let plain = SecKeyCreateDecryptedData(key, .rsaEncryptionPKCS1, cipher as CFData, &error) else {
            throw DecryptError.rsaFailed
        }
        return plain as Data
    }

    // MARK: - byte transforms

    /// ABCD → CDAB for every complete 4-byte block. Its own inverse.
    static func swapBlockHalves(_ bytes: [UInt8]) -> [UInt8] {
        var r = bytes
        let full = r.count - (r.count % 4)
        var i = 0
        while i < full {
            r.swapAt(i, i + 2); r.swapAt(i + 1, i + 3)
            i += 4
        }
        return r
    }

    /// ABCD → BADC — swap adjacent bytes in pairs.
    static func swapAdjacent(_ bytes: [UInt8]) -> [UInt8] {
        var r = bytes
        var i = 0
        while i + 1 < r.count { r.swapAt(i, i + 1); i += 2 }
        return r
    }

    private static func latin(_ bytes: [UInt8]) -> String {
        String(bytes.map { Character(UnicodeScalar($0)) })
    }

    // MARK: - parsing

    private static func parse(_ link: String) -> (mode: Int, body: String)? {
        let s = link.trimmingCharacters(in: .whitespacesAndNewlines)
        for (prefix, mode) in prefixes where s.hasPrefix(prefix) {
            return (mode, String(s.dropFirst(prefix.count)))
        }
        return nil
    }

    /// Standard or URL-safe base64, whitespace- and padding-tolerant.
    static func base64Decode(_ text: String) -> Data? {
        var s = text.filter { !$0.isWhitespace }
        s = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while s.hasSuffix("=") { s.removeLast() }
        let pad = (4 - s.count % 4) % 4
        s += String(repeating: "=", count: pad)
        return Data(base64Encoded: s)
    }
}

/// Lazily-loaded, cached Happ key material (bundled JSON → `SecKey`).
private final class HappKeyStore: @unchecked Sendable {
    static let shared = HappKeyStore()
    let native: [SecKey]                 // crypt1…4, index = mode
    let crypt5: [String: SecKey]         // marker → key

    private init() {
        native = HappKeyStore.loadNative()
        crypt5 = HappKeyStore.loadCrypt5()
    }

    private static func loadNative() -> [SecKey] {
        guard let url = Bundle.module.url(forResource: "native_keys", withExtension: "json", subdirectory: "HappKeys"),
              let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = obj["keys"] as? [String] else { return [] }
        return arr.compactMap { rsaKey(fromPKCS1Base64: $0) }
    }

    private static func loadCrypt5() -> [String: SecKey] {
        guard let url = Bundle.module.url(forResource: "crypt5_keys", withExtension: "json", subdirectory: "HappKeys"),
              let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return [:] }
        return obj.reduce(into: [:]) { acc, kv in
            if let der = Data(base64Encoded: kv.value),
               let pkcs1 = pkcs1(fromPKCS8: der),
               let key = rsaKey(fromPKCS1: pkcs1) { acc[kv.key] = key }
        }
    }

    private static func rsaKey(fromPKCS1Base64 b64: String) -> SecKey? {
        guard let der = Data(base64Encoded: b64) else { return nil }
        return rsaKey(fromPKCS1: der)
    }

    private static func rsaKey(fromPKCS1 der: Data) -> SecKey? {
        let attrs: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate,
        ]
        return SecKeyCreateWithData(der as CFData, attrs as CFDictionary, nil)
    }

    /// Strip the PKCS#8 PrivateKeyInfo wrapper to the inner PKCS#1 RSAPrivateKey.
    /// SEQUENCE { INTEGER version, SEQUENCE algId, OCTET STRING pkcs1 }.
    private static func pkcs1(fromPKCS8 der: Data) -> Data? {
        let b = [UInt8](der)
        var p = 0
        func readTLV() -> (tag: UInt8, value: ArraySlice<UInt8>)? {
            guard p < b.count else { return nil }
            let tag = b[p]; p += 1
            guard p < b.count else { return nil }
            var len = Int(b[p]); p += 1
            if len & 0x80 != 0 {
                let n = len & 0x7F
                guard n > 0, n <= 4, p + n <= b.count else { return nil }
                len = 0
                for _ in 0..<n { len = (len << 8) | Int(b[p]); p += 1 }
            }
            guard p + len <= b.count else { return nil }
            let value = b[p ..< p + len]; p += len
            return (tag, value)
        }
        guard let outer = readTLV(), outer.tag == 0x30 else { return nil }
        p = outer.value.startIndex
        guard readTLV()?.tag == 0x02 else { return nil }   // version INTEGER
        guard readTLV()?.tag == 0x30 else { return nil }   // algorithm SEQUENCE
        guard let octet = readTLV(), octet.tag == 0x04 else { return nil } // OCTET STRING
        return Data(octet.value)
    }
}
