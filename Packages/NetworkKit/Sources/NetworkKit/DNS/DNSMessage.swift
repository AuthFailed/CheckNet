import Foundation

/// Encodes DNS queries and decodes responses (RFC 1035 + EDNS0 for DNSSEC DO bit).
enum DNSMessage {

    // MARK: Encoding

    static func encodeQuery(id: UInt16, name: String, type: DNSRecordType, dnssec: Bool) -> [UInt8] {
        var bytes = [UInt8]()
        // Header
        bytes.append(UInt8(id >> 8)); bytes.append(UInt8(id & 0xFF))
        let flags: UInt16 = 0x0100 // RD = 1
        bytes.append(UInt8(flags >> 8)); bytes.append(UInt8(flags & 0xFF))
        appendUInt16(&bytes, 1)                 // QDCOUNT
        appendUInt16(&bytes, 0)                 // ANCOUNT
        appendUInt16(&bytes, 0)                 // NSCOUNT
        appendUInt16(&bytes, 1)                 // ARCOUNT (always an OPT record)

        // Question
        bytes.append(contentsOf: encodeName(name))
        appendUInt16(&bytes, type.rawValue)     // QTYPE
        appendUInt16(&bytes, 1)                 // QCLASS = IN

        // EDNS0 OPT pseudo-record: raises the UDP payload limit to 4096 and,
        // when requested, sets the DNSSEC DO bit.
        bytes.append(0)                         // root name
        appendUInt16(&bytes, 41)                // type OPT
        appendUInt16(&bytes, 4096)              // UDP payload size (class field)
        // TTL: ext-rcode(1) | version(1) | flags(2, DO=0x8000)
        bytes.append(0); bytes.append(0)
        appendUInt16(&bytes, dnssec ? 0x8000 : 0)
        appendUInt16(&bytes, 0)                 // RDLEN
        return bytes
    }

    private static func appendUInt16(_ bytes: inout [UInt8], _ value: UInt16) {
        bytes.append(UInt8(value >> 8)); bytes.append(UInt8(value & 0xFF))
    }

    static func encodeName(_ name: String) -> [UInt8] {
        var bytes = [UInt8]()
        let trimmed = name.hasSuffix(".") ? String(name.dropLast()) : name
        if !trimmed.isEmpty {
            for label in trimmed.split(separator: ".") {
                let l = Array(label.utf8)
                bytes.append(UInt8(min(l.count, 63)))
                bytes.append(contentsOf: l.prefix(63))
            }
        }
        bytes.append(0)
        return bytes
    }

    // MARK: Decoding

    struct Header {
        var id: UInt16
        var flags: UInt16
        var qd: Int, an: Int, ns: Int, ar: Int
        var rcode: Int { Int(flags & 0x000F) }
        var truncated: Bool { (flags & 0x0200) != 0 }
        var authenticated: Bool { (flags & 0x0020) != 0 } // AD bit
    }

    struct Decoded {
        var header: Header
        var answers: [DNSRecord]
        var authorities: [DNSRecord]
        var additionals: [DNSRecord]
    }

    static func decode(_ data: [UInt8]) throws -> Decoded {
        guard data.count >= 12 else { throw NetworkError.protocolError("DNS-ответ слишком короткий") }
        var p = 0
        func u16() throws -> UInt16 {
            guard p + 1 < data.count else { throw NetworkError.protocolError("выход за пределы") }
            let v = (UInt16(data[p]) << 8) | UInt16(data[p + 1]); p += 2; return v
        }
        let header = Header(
            id: try u16(), flags: try u16(),
            qd: Int(try u16()), an: Int(try u16()), ns: Int(try u16()), ar: Int(try u16())
        )

        // Skip questions.
        for _ in 0..<header.qd {
            _ = try readName(data, &p)
            p += 4 // qtype + qclass
        }

        func readRecords(_ count: Int) throws -> [DNSRecord] {
            var records: [DNSRecord] = []
            for _ in 0..<count {
                guard p < data.count else { break }
                let name = try readName(data, &p)
                let rawType = try u16()
                _ = try u16() // class
                guard p + 3 < data.count else { break }
                let ttl = (UInt32(data[p]) << 24) | (UInt32(data[p+1]) << 16) | (UInt32(data[p+2]) << 8) | UInt32(data[p+3])
                p += 4
                let rdlen = Int(try u16())
                guard p + rdlen <= data.count else { break }
                let rdataStart = p
                let type = DNSRecordType(rawValue: rawType)
                let value = decodeRData(data, type: rawType, start: rdataStart, length: rdlen)
                p = rdataStart + rdlen
                // Skip OPT pseudo-records in the record list.
                if rawType == 41 { continue }
                records.append(DNSRecord(name: name, type: type, rawType: rawType, ttl: ttl, value: value))
            }
            return records
        }

        let answers = try readRecords(header.an)
        let authorities = try readRecords(header.ns)
        let additionals = try readRecords(header.ar)
        return Decoded(header: header, answers: answers, authorities: authorities, additionals: additionals)
    }

    /// Reads a (possibly compressed) domain name starting at `p`, advancing `p` past it.
    ///
    /// Names arrive from untrusted resolvers, so every deviation from RFC 1035 is a
    /// hard error rather than a best-effort guess. A compression pointer must lead
    /// strictly backwards — a forward, self-referential, or cyclic pointer is the
    /// classic decompression-loop DoS — the encoded name may not exceed 255 bytes,
    /// and a label's two high bits must be clear. Together these bound the work on
    /// hostile input and guarantee termination.
    private static func readName(_ data: [UInt8], _ p: inout Int) throws -> String {
        var labels: [String] = []
        var jumped = false
        var cursor = p
        var nameLength = 0
        var pointerHops = 0
        while cursor < data.count {
            let len = data[cursor]
            if len == 0 {
                cursor += 1
                if !jumped { p = cursor }
                break
            }
            if (len & 0xC0) == 0xC0 {
                // Compression pointer: two bytes, low 14 bits are the target offset.
                guard cursor + 1 < data.count else {
                    throw NetworkError.protocolError("обрезанный указатель сжатия DNS")
                }
                let pointer = (Int(len & 0x3F) << 8) | Int(data[cursor + 1])
                if !jumped { p = cursor + 2 }
                // A valid pointer always references an earlier position; anything
                // else (forward, self, or a cycle) would loop forever.
                guard pointer < cursor else {
                    throw NetworkError.protocolError("указатель сжатия DNS не ведёт назад")
                }
                pointerHops += 1
                guard pointerHops <= data.count else {
                    throw NetworkError.protocolError("слишком много указателей сжатия DNS")
                }
                jumped = true
                cursor = pointer
                continue
            }
            // The two high bits of a label length are reserved and must be zero.
            guard (len & 0xC0) == 0 else {
                throw NetworkError.protocolError("недопустимая длина метки DNS")
            }
            let start = cursor + 1
            let end = start + Int(len)
            guard end <= data.count else {
                throw NetworkError.protocolError("метка DNS выходит за пределы пакета")
            }
            nameLength += Int(len) + 1
            guard nameLength <= 255 else {
                throw NetworkError.protocolError("имя DNS длиннее 255 байт")
            }
            labels.append(String(decoding: data[start..<end], as: UTF8.self))
            cursor = end
        }
        if !jumped { p = cursor }
        return labels.isEmpty ? "." : labels.joined(separator: ".")
    }

    private static func decodeRData(_ data: [UInt8], type: UInt16, start: Int, length: Int) -> String {
        let end = start + length
        guard end <= data.count else { return "" }
        switch type {
        case 1: // A
            guard length == 4 else { return "" }
            return "\(data[start]).\(data[start+1]).\(data[start+2]).\(data[start+3])"
        case 28: // AAAA
            guard length == 16 else { return "" }
            var parts: [String] = []
            var i = start
            while i < end { parts.append(String(format: "%02x%02x", data[i], data[i+1])); i += 2 }
            return compressIPv6(parts.joined(separator: ":"))
        case 5, 2, 12: // CNAME, NS, PTR
            var pp = start
            return (try? readName(data, &pp)) ?? ""
        case 15: // MX
            guard length >= 3 else { return "" }
            let pref = (UInt16(data[start]) << 8) | UInt16(data[start+1])
            var pp = start + 2
            let exch = (try? readName(data, &pp)) ?? ""
            return "\(pref) \(exch)"
        case 16: // TXT
            var pp = start
            var chunks: [String] = []
            while pp < end {
                let l = Int(data[pp]); pp += 1
                guard pp + l <= end else { break }
                chunks.append(String(decoding: data[pp..<pp+l], as: UTF8.self))
                pp += l
            }
            return "\"" + chunks.joined() + "\""
        case 6: // SOA
            var pp = start
            let mname = (try? readName(data, &pp)) ?? ""
            let rname = (try? readName(data, &pp)) ?? ""
            guard pp + 20 <= end else { return "\(mname) \(rname)" }
            func u32(_ o: Int) -> UInt32 {
                (UInt32(data[o]) << 24) | (UInt32(data[o+1]) << 16) | (UInt32(data[o+2]) << 8) | UInt32(data[o+3])
            }
            let serial = u32(pp)
            return "\(mname) \(rname) \(serial)"
        case 33: // SRV
            guard length >= 6 else { return "" }
            let prio = (UInt16(data[start]) << 8) | UInt16(data[start+1])
            let weight = (UInt16(data[start+2]) << 8) | UInt16(data[start+3])
            let port = (UInt16(data[start+4]) << 8) | UInt16(data[start+5])
            var pp = start + 6
            let target = (try? readName(data, &pp)) ?? ""
            return "\(prio) \(weight) \(port) \(target)"
        case 257: // CAA
            guard length >= 2 else { return "" }
            let flags = data[start]
            let tagLen = Int(data[start+1])
            guard start + 2 + tagLen <= end else { return "" }
            let tag = String(decoding: data[start+2..<start+2+tagLen], as: UTF8.self)
            let value = String(decoding: data[start+2+tagLen..<end], as: UTF8.self)
            return "\(flags) \(tag) \"\(value)\""
        case 65: // HTTPS (SVCB)
            guard length >= 2 else { return "" }
            let prio = (UInt16(data[start]) << 8) | UInt16(data[start+1])
            var pp = start + 2
            let target = (try? readName(data, &pp)) ?? "."
            return "\(prio) \(target == "." ? "(self)" : target)"
        default:
            return "\(length) байт"
        }
    }

    private static func compressIPv6(_ full: String) -> String {
        // Collapse the longest run of zero groups into "::".
        let groups = full.split(separator: ":").map { String(Int($0, radix: 16) ?? 0, radix: 16) }
        var bestStart = -1, bestLen = 0, curStart = -1, curLen = 0
        for (i, g) in groups.enumerated() {
            if g == "0" {
                if curStart < 0 { curStart = i; curLen = 1 } else { curLen += 1 }
                if curLen > bestLen { bestLen = curLen; bestStart = curStart }
            } else { curStart = -1; curLen = 0 }
        }
        if bestLen < 2 { return groups.joined(separator: ":") }
        var result = groups[0..<bestStart].joined(separator: ":")
        result += "::"
        result += groups[(bestStart + bestLen)...].joined(separator: ":")
        return result
    }
}
