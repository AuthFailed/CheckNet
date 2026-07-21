import Foundation
import CryptoKit

/// Builds a raw TLS 1.3 ClientHello, byte for byte.
///
/// Network.framework won't let us shape the handshake — extension order, GREASE
/// and the cipher list come from Apple's stack — so a faithful browser
/// fingerprint has to be assembled by hand and written straight to a socket.
///
/// This is for *detection only*: we send the ClientHello and look at how the
/// path reacts (ServerHello, RST, or silence). We never complete the handshake
/// or move data, so nothing here helps circumvent anything.
struct ClientHelloBuilder {
    let profile: JA3Profile
    let serverName: String

    /// TLS extension type codes.
    private enum Ext {
        static let serverName: UInt16 = 0
        static let statusRequest: UInt16 = 5
        static let supportedGroups: UInt16 = 10
        static let ecPointFormats: UInt16 = 11
        static let signatureAlgorithms: UInt16 = 13
        static let alpn: UInt16 = 16
        static let signedCertTimestamp: UInt16 = 18
        static let padding: UInt16 = 21
        static let extendedMasterSecret: UInt16 = 23
        static let compressCertificate: UInt16 = 27
        static let recordSizeLimit: UInt16 = 28
        static let sessionTicket: UInt16 = 35
        static let delegatedCredentials: UInt16 = 34
        static let supportedVersions: UInt16 = 43
        static let pskKeyExchangeModes: UInt16 = 45
        static let keyShare: UInt16 = 51
        static let renegotiationInfo: UInt16 = 0xff01
        static let applicationSettings: UInt16 = 0x4469 // ALPS, Chrome
    }

    /// GREASE values chosen once per handshake. BoringSSL (Chrome) reuses a
    /// single seeded value across cipher/group/version/key_share and uses two
    /// distinct values for the two GREASE *extensions* — reproduce that, because
    /// strict servers reject independently-random GREASE (observed as an
    /// illegal_parameter alert).
    private struct GREASESet {
        let shared: UInt16   // cipher, groups, versions, key_share
        let ext1: UInt16     // first GREASE extension
        let ext2: UInt16     // second GREASE extension (distinct from ext1)
    }

    /// Returns the full TLS record ready to write to a socket.
    func build<G: RandomNumberGenerator>(using rng: inout G) -> [UInt8] {
        let greaseTable = Self.greaseTable
        let base = Int.random(in: 0..<greaseTable.count, using: &rng)
        let grease = GREASESet(
            shared: greaseTable[base],
            ext1: greaseTable[base],
            ext2: greaseTable[(base + 8) % greaseTable.count]
        )
        // The X25519 public key placed in key_share must be a real point, or a
        // strict server rejects the share; a genuine ephemeral key is cheapest.
        let keyShare = Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation

        var random = [UInt8](repeating: 0, count: 32)
        for i in random.indices { random[i] = UInt8.random(in: 0...255, using: &rng) }
        var sessionID = [UInt8](repeating: 0, count: 32)
        for i in sessionID.indices { sessionID[i] = UInt8.random(in: 0...255, using: &rng) }

        var body: [UInt8] = []
        body += [0x03, 0x03]                       // legacy_version = TLS 1.2
        body += random
        body += [UInt8(sessionID.count)] + sessionID

        body += lengthPrefixed16(cipherSuites(grease: grease))   // cipher_suites
        body += [0x01, 0x00]                       // compression_methods = null

        body += lengthPrefixed16(extensions(keyShare: Array(keyShare), grease: grease))

        // Handshake header (type 0x01) + 3-byte length.
        var handshake: [UInt8] = [0x01]
        handshake += length24(body.count)
        handshake += body

        // Record header: handshake (0x16), legacy record version TLS 1.0.
        var record: [UInt8] = [0x16, 0x03, 0x01]
        record += length16(handshake.count)
        record += handshake
        return record
    }

    // MARK: - Cipher suites

    private func cipherSuites(grease: GREASESet) -> [UInt8] {
        var out: [UInt8] = []
        if profile.usesGREASE { out += be16(grease.shared) }
        for suite in profile.cipherSuites { out += be16(suite) }
        return out
    }

    // MARK: - Extensions

    private func extensions(keyShare: [UInt8], grease: GREASESet) -> [UInt8] {
        var built: [(UInt16, [UInt8])] = []

        // Two GREASE extensions must have distinct types (no duplicate extension
        // is allowed), so the second draws ext2.
        var greaseExtensionIndex = 0
        func nextGREASEExtension() -> UInt16 {
            defer { greaseExtensionIndex += 1 }
            return greaseExtensionIndex == 0 ? grease.ext1 : grease.ext2
        }

        for kind in profile.extensionOrder {
            switch kind {
            case .grease:
                // GREASE extensions carry an empty body.
                built.append((nextGREASEExtension(), []))
            case .serverName:
                built.append((Ext.serverName, serverNameExtension()))
            case .extendedMasterSecret:
                built.append((Ext.extendedMasterSecret, []))
            case .renegotiationInfo:
                built.append((Ext.renegotiationInfo, [0x00]))
            case .supportedGroups:
                built.append((Ext.supportedGroups, supportedGroupsExtension(grease: grease)))
            case .ecPointFormats:
                built.append((Ext.ecPointFormats, [0x01, 0x00]))
            case .sessionTicket:
                built.append((Ext.sessionTicket, []))
            case .alpn:
                built.append((Ext.alpn, alpnExtension()))
            case .statusRequest:
                built.append((Ext.statusRequest, [0x01, 0x00, 0x00, 0x00, 0x00]))
            case .signatureAlgorithms:
                built.append((Ext.signatureAlgorithms, lengthPrefixed16(profile.signatureAlgorithms.flatMap(be16))))
            case .signedCertTimestamp:
                built.append((Ext.signedCertTimestamp, []))
            case .keyShare:
                built.append((Ext.keyShare, keyShareExtension(publicKey: keyShare, grease: grease)))
            case .pskKeyExchangeModes:
                built.append((Ext.pskKeyExchangeModes, [0x01, 0x01]))
            case .supportedVersions:
                built.append((Ext.supportedVersions, supportedVersionsExtension(grease: grease)))
            case .compressCertificate:
                built.append((Ext.compressCertificate, [0x02, 0x00, 0x02])) // brotli
            case .applicationSettings:
                built.append((Ext.applicationSettings, [0x00, 0x03, 0x02, 0x68, 0x32])) // "h2"
            case .delegatedCredentials:
                built.append((Ext.delegatedCredentials, [0x00, 0x0a, 0x04, 0x03, 0x05, 0x03, 0x06, 0x03, 0x02, 0x03, 0x02, 0x02]))
            case .recordSizeLimit:
                built.append((Ext.recordSizeLimit, [0x40, 0x01]))
            case .padding:
                built.append((Ext.padding, [])) // filled below to a target size
            }
        }

        var out: [UInt8] = []
        for (type, data) in built where type != Ext.padding {
            out += be16(type) + lengthPrefixed16(data)
        }
        // Chrome pads the ClientHello so its total length lands in 512-byte
        // bands; approximate that when the profile asks for padding.
        if profile.extensionOrder.contains(.padding) {
            let target = 512
            let current = out.count + 4 // + padding ext header
            if current < target {
                let padLen = target - current
                out += be16(Ext.padding) + lengthPrefixed16([UInt8](repeating: 0, count: padLen))
            }
        }
        return out
    }

    private func serverNameExtension() -> [UInt8] {
        let host = Array(serverName.utf8)
        var entry: [UInt8] = [0x00] // name_type = host_name
        entry += length16(host.count) + host
        return lengthPrefixed16(entry)
    }

    private func alpnExtension() -> [UInt8] {
        var list: [UInt8] = []
        for proto in profile.alpn {
            let bytes = Array(proto.utf8)
            list += [UInt8(bytes.count)] + bytes
        }
        return lengthPrefixed16(list)
    }

    private func supportedGroupsExtension(grease: GREASESet) -> [UInt8] {
        var groups: [UInt8] = []
        if profile.usesGREASE { groups += be16(grease.shared) }
        for group in profile.supportedGroups { groups += be16(group) }
        return lengthPrefixed16(groups)
    }

    private func supportedVersionsExtension(grease: GREASESet) -> [UInt8] {
        var versions: [UInt8] = []
        if profile.usesGREASE { versions += be16(grease.shared) }
        versions += [0x03, 0x04, 0x03, 0x03] // TLS 1.3, TLS 1.2
        return [UInt8(versions.count)] + versions
    }

    private func keyShareExtension(publicKey: [UInt8], grease: GREASESet) -> [UInt8] {
        var shares: [UInt8] = []
        if profile.usesGREASE {
            // GREASE key share with a single zero byte.
            shares += be16(grease.shared) + length16(1) + [0x00]
        }
        shares += be16(0x001d) + length16(publicKey.count) + publicKey // x25519
        return lengthPrefixed16(shares)
    }

    // MARK: - GREASE

    /// The 16 GREASE values of the form 0x?A?A (RFC 8701).
    private static let greaseTable: [UInt16] = [
        0x0a0a, 0x1a1a, 0x2a2a, 0x3a3a, 0x4a4a, 0x5a5a, 0x6a6a, 0x7a7a,
        0x8a8a, 0x9a9a, 0xaaaa, 0xbaba, 0xcaca, 0xdada, 0xeaea, 0xfafa
    ]


    // MARK: - Byte helpers

    private func be16(_ value: UInt16) -> [UInt8] { [UInt8(value >> 8), UInt8(value & 0xff)] }
    private func length16(_ n: Int) -> [UInt8] { [UInt8((n >> 8) & 0xff), UInt8(n & 0xff)] }
    private func length24(_ n: Int) -> [UInt8] { [UInt8((n >> 16) & 0xff), UInt8((n >> 8) & 0xff), UInt8(n & 0xff)] }
    private func lengthPrefixed16(_ data: [UInt8]) -> [UInt8] { length16(data.count) + data }
}
