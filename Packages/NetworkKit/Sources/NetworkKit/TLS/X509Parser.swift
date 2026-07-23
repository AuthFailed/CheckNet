import Foundation

/// A minimal X.509 / ASN.1 DER parser to extract certificate fields that have
/// no cross-platform Security.framework API on iOS (issuer, validity, CA flag).
enum X509 {
    struct Fields {
        var issuer: String
        var subject: String
        var notBefore: Date?
        var notAfter: Date?
        var isCA: Bool
        var subjectAltNames: [String]
    }

    static func parse(der: [UInt8]) -> Fields? {
        var i = 0
        guard let cert = readHeader(der, &i), cert.tag == 0x30 else { return nil }        // Certificate SEQUENCE
        guard let tbs = readHeader(der, &i), tbs.tag == 0x30 else { return nil }           // tbsCertificate SEQUENCE
        let tbsEnd = i + tbs.len

        // Optional version [0] EXPLICIT
        if i < der.count, der[i] == 0xA0 {
            guard let v = readHeader(der, &i) else { return nil }
            i += v.len
        }
        // serialNumber INTEGER — skip.
        guard let serial = readHeader(der, &i) else { return nil }
        i += serial.len
        // signature AlgorithmIdentifier SEQUENCE — skip.
        guard let alg = readHeader(der, &i), alg.tag == 0x30 else { return nil }
        i += alg.len
        // issuer Name SEQUENCE
        guard let issuer = readHeader(der, &i), issuer.tag == 0x30 else { return nil }
        let issuerStr = parseName(der, start: i, end: i + issuer.len)
        i += issuer.len
        // validity SEQUENCE { notBefore, notAfter }
        guard let validity = readHeader(der, &i), validity.tag == 0x30 else { return nil }
        var vi = i
        let notBefore = readTime(der, &vi)
        let notAfter = readTime(der, &vi)
        i += validity.len
        // subject Name SEQUENCE
        guard let subject = readHeader(der, &i), subject.tag == 0x30 else { return nil }
        let subjectStr = parseName(der, start: i, end: i + subject.len)
        i += subject.len

        // Scan remaining TBS (the extensions block) for BasicConstraints
        // CA:TRUE (OID 2.5.29.19) and SubjectAltName (OID 2.5.29.17).
        let extEnd = min(tbsEnd, der.count)
        let isCA = scanForCA(der, start: i, end: extEnd)
        let sans = parseSAN(der, start: i, end: extEnd)

        return Fields(issuer: issuerStr, subject: subjectStr, notBefore: notBefore,
                      notAfter: notAfter, isCA: isCA, subjectAltNames: sans)
    }

    // MARK: TLV

    private static func readHeader(_ b: [UInt8], _ i: inout Int) -> (tag: UInt8, len: Int)? {
        guard i < b.count else { return nil }
        let tag = b[i]; i += 1
        guard i < b.count else { return nil }
        var len = Int(b[i]); i += 1
        if len & 0x80 != 0 {
            let n = len & 0x7F
            guard n <= 4 else { return nil }
            len = 0
            for _ in 0..<n {
                guard i < b.count else { return nil }
                len = (len << 8) | Int(b[i]); i += 1
            }
        }
        guard i + len <= b.count else { return nil }
        return (tag, len)
    }

    // MARK: Name

    private static func parseName(_ b: [UInt8], start: Int, end: Int) -> String {
        var i = start
        var parts: [String] = []
        while i < end {
            guard let rdn = readHeader(b, &i), rdn.tag == 0x31 else { break }  // SET
            let setEnd = i + rdn.len
            while i < setEnd {
                guard let atv = readHeader(b, &i), atv.tag == 0x30 else { break } // SEQUENCE
                let atvEnd = i + atv.len
                guard let oid = readHeader(b, &i), oid.tag == 0x06 else { i = atvEnd; continue }
                let oidBytes = Array(b[i..<i+oid.len])
                i += oid.len
                guard let val = readHeader(b, &i) else { break }
                let str = decodeDirectoryString(tag: val.tag, b[i..<min(i+val.len, b.count)])
                i += val.len
                if let label = oidLabel(oidBytes) {
                    parts.append("\(label)=\(str)")
                }
                i = atvEnd
            }
            i = setEnd
        }
        // Prefer CN for a compact display but keep full DN available.
        if let cn = parts.first(where: { $0.hasPrefix("CN=") }) {
            let others = parts.filter { !$0.hasPrefix("CN=") }
            return others.isEmpty ? cn : cn + ", " + others.joined(separator: ", ")
        }
        return parts.joined(separator: ", ")
    }

    private static func oidLabel(_ oid: [UInt8]) -> String? {
        switch oid {
        case [0x55, 0x04, 0x03]: return "CN"
        case [0x55, 0x04, 0x0A]: return "O"
        case [0x55, 0x04, 0x0B]: return "OU"
        case [0x55, 0x04, 0x06]: return "C"
        case [0x55, 0x04, 0x08]: return "ST"
        case [0x55, 0x04, 0x07]: return "L"
        default: return nil
        }
    }

    /// Decodes an ASN.1 DirectoryString by its tag. UTF8String/PrintableString/
    /// IA5String are ASCII-compatible, BMPString is UTF-16BE, and TeletexString
    /// (T.61) is treated as Latin-1 — the pragmatic reading real certificates use.
    private static func decodeDirectoryString(tag: UInt8, _ bytes: ArraySlice<UInt8>) -> String {
        switch tag {
        case 0x1E: // BMPString
            return String(data: Data(bytes), encoding: .utf16BigEndian)
                ?? String(decoding: bytes, as: UTF8.self)
        case 0x14: // TeletexString / T61String
            return String(data: Data(bytes), encoding: .isoLatin1)
                ?? String(decoding: bytes, as: UTF8.self)
        default:   // UTF8String, PrintableString, IA5String, …
            return String(decoding: bytes, as: UTF8.self)
        }
    }

    // MARK: SubjectAltName

    /// Extracts dNSName and iPAddress entries from the SubjectAltName extension
    /// (OID 2.5.29.17). Malformed extensions yield an empty list, never a throw.
    private static func parseSAN(_ b: [UInt8], start: Int, end: Int) -> [String] {
        guard end > start, end <= b.count else { return [] }
        // Locate the extnID OID TLV: 06 03 55 1D 11.
        var i = start
        while i + 4 < end {
            if b[i] == 0x06, b[i+1] == 0x03, b[i+2] == 0x55, b[i+3] == 0x1D, b[i+4] == 0x11 {
                return decodeSAN(b, oidEnd: i + 5, hardEnd: end)
            }
            i += 1
        }
        return []
    }

    private static func decodeSAN(_ b: [UInt8], oidEnd: Int, hardEnd: Int) -> [String] {
        var i = oidEnd
        // Optional critical BOOLEAN (01 01 xx) between extnID and extnValue.
        if i + 2 < hardEnd, b[i] == 0x01, b[i+1] == 0x01 { i += 3 }
        // extnValue OCTET STRING wraps the GeneralNames DER.
        guard i < hardEnd, b[i] == 0x04, let octet = readHeader(b, &i) else { return [] }
        let innerEnd = min(i + octet.len, b.count)
        // GeneralNames ::= SEQUENCE OF GeneralName.
        guard i < innerEnd, b[i] == 0x30, let seq = readHeader(b, &i) else { return [] }
        let namesEnd = min(i + seq.len, innerEnd)
        var names: [String] = []
        while i < namesEnd {
            guard let gn = readHeader(b, &i) else { break }
            let valStart = i
            let valEnd = min(i + gn.len, namesEnd)
            switch gn.tag {
            case 0x82: // dNSName — context [2] IA5String
                names.append(String(decoding: b[valStart..<valEnd], as: UTF8.self))
            case 0x87: // iPAddress — context [7] OCTET STRING
                names.append(formatIPAddress(Array(b[valStart..<valEnd])))
            default:
                break      // rfc822Name, uniformResourceIdentifier, … not surfaced
            }
            i = valEnd
        }
        return names
    }

    private static func formatIPAddress(_ bytes: [UInt8]) -> String {
        if bytes.count == 4 {
            return bytes.map(String.init).joined(separator: ".")
        }
        if bytes.count == 16 {
            var groups: [String] = []
            var i = 0
            while i < 16 { groups.append(String(format: "%02x%02x", bytes[i], bytes[i+1])); i += 2 }
            return groups.joined(separator: ":")
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Time

    private static func readTime(_ b: [UInt8], _ i: inout Int) -> Date? {
        guard let h = readHeader(b, &i) else { return nil }
        let raw = String(decoding: b[i..<i+h.len], as: UTF8.self)
        i += h.len
        switch h.tag {
        case 0x17: return parseUTCTime(raw)          // UTCTime YYMMDDHHMMSSZ
        case 0x18: return parseGeneralizedTime(raw)  // GeneralizedTime YYYYMMDDHHMMSSZ
        default:   return nil
        }
    }

    /// UTCTime uses a two-digit year. RFC 5280 §4.1.2.5.1 fixes the century:
    /// 00–49 → 2000–2049, 50–99 → 1950–1999. `DateFormatter`'s own sliding
    /// window does not follow that rule, so the year is resolved by hand.
    private static func parseUTCTime(_ s: String) -> Date? {
        let d = Array(s)
        guard d.count >= 12, let yy = int(d, 0, 2), let rest = components(d, from: 2) else {
            return dateViaFormatter(s, format: "yyMMddHHmmss'Z'")
        }
        let year = yy < 50 ? 2000 + yy : 1900 + yy
        return utcDate(year: year, rest)
    }

    private static func parseGeneralizedTime(_ s: String) -> Date? {
        let d = Array(s)
        guard d.count >= 14, let year = int(d, 0, 4), let rest = components(d, from: 4) else {
            return dateViaFormatter(s, format: "yyyyMMddHHmmss'Z'")
        }
        return utcDate(year: year, rest)
    }

    /// Parses MMDDHHMMSS starting at `offset` into (month, day, hour, minute, second).
    private static func components(_ d: [Character], from offset: Int) -> (Int, Int, Int, Int, Int)? {
        guard let mo = int(d, offset, offset + 2), let da = int(d, offset + 2, offset + 4),
              let hh = int(d, offset + 4, offset + 6), let mi = int(d, offset + 6, offset + 8),
              let se = int(d, offset + 8, offset + 10) else { return nil }
        return (mo, da, hh, mi, se)
    }

    private static func int(_ d: [Character], _ a: Int, _ b: Int) -> Int? {
        guard b <= d.count else { return nil }
        return Int(String(d[a..<b]))
    }

    private static func utcDate(year: Int, _ c: (Int, Int, Int, Int, Int)) -> Date? {
        var comps = DateComponents()
        comps.timeZone = TimeZone(identifier: "UTC")
        comps.year = year; comps.month = c.0; comps.day = c.1
        comps.hour = c.2; comps.minute = c.3; comps.second = c.4
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: comps)
    }

    /// Fallback for non-canonical encodings (offsets, omitted seconds).
    private static func dateViaFormatter(_ s: String, format: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = format
        return f.date(from: s)
    }

    // MARK: CA flag

    private static func scanForCA(_ b: [UInt8], start: Int, end: Int) -> Bool {
        // Look for the BasicConstraints OID 2.5.29.19 == 55 1D 13 followed
        // shortly by a BOOLEAN TRUE (01 01 FF).
        guard end > start, end <= b.count else { return false }
        var i = start
        while i + 2 < end {
            if b[i] == 0x55, b[i+1] == 0x1D, b[i+2] == 0x13 {
                var j = i + 3
                while j + 2 < min(i + 24, end) {
                    if b[j] == 0x01, b[j+1] == 0x01, b[j+2] == 0xFF { return true }
                    j += 1
                }
            }
            i += 1
        }
        return false
    }
}
