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

        // Scan remaining TBS for BasicConstraints CA:TRUE (OID 2.5.29.19).
        let isCA = scanForCA(der, start: i, end: min(tbsEnd, der.count))

        return Fields(issuer: issuerStr, subject: subjectStr, notBefore: notBefore, notAfter: notAfter, isCA: isCA)
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
                let str = String(decoding: b[i..<min(i+val.len, b.count)], as: UTF8.self)
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

    // MARK: Time

    private static func readTime(_ b: [UInt8], _ i: inout Int) -> Date? {
        guard let h = readHeader(b, &i) else { return nil }
        let raw = String(decoding: b[i..<i+h.len], as: UTF8.self)
        i += h.len
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        if h.tag == 0x17 {           // UTCTime YYMMDDHHMMSSZ
            formatter.dateFormat = "yyMMddHHmmss'Z'"
        } else if h.tag == 0x18 {    // GeneralizedTime YYYYMMDDHHMMSSZ
            formatter.dateFormat = "yyyyMMddHHmmss'Z'"
        } else {
            return nil
        }
        return formatter.date(from: raw)
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
