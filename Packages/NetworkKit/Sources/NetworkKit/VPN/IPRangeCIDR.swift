import Foundation

/// Expands an inclusive [from, to] IP range (mihomo stores merged ranges) into
/// the minimal set of aligned CIDR blocks — the notation the rules were written
/// in. Works on big-endian byte arrays so IPv4 (4 bytes) and IPv6 (16 bytes)
/// share one code path with no 128-bit integer type (keeps the iOS 17 floor).
enum IPRangeCIDR {
    static func blocks(from16 f: [UInt8], to16 t: [UInt8]) -> [String] {
        guard f.count == 16, t.count == 16 else { return [] }
        let v4 = isV4Mapped(f) && isV4Mapped(t)
        let from = v4 ? Array(f[12 ..< 16]) : f
        let to = v4 ? Array(t[12 ..< 16]) : t
        guard compare(from, to) <= 0 else { return [] }
        return cidrBlocks(from: from, to: to).map { render($0.base, prefix: $0.prefix, v4: v4) }
    }

    /// Greedily emit the largest aligned block from `cur` that still fits within
    /// `to`, then advance — the standard range→CIDR split.
    static func cidrBlocks(from: [UInt8], to: [UInt8]) -> [(base: [UInt8], prefix: Int)] {
        let width = from.count * 8
        var out: [(base: [UInt8], prefix: Int)] = []
        var cur = from
        while compare(cur, to) <= 0 {
            var nbits = min(trailingZeros(cur), width)                 // block size by alignment
            while nbits > 0, compare(orLowBits(cur, nbits), to) > 0 {  // shrink until it fits
                nbits -= 1
            }
            out.append((cur, width - nbits))
            let (next, overflow) = addPow2(cur, nbits)
            if overflow { break }
            cur = next
        }
        return out
    }

    // MARK: - big-endian byte math

    /// Lexicographic compare of equal-length big-endian arrays: -1 / 0 / 1.
    static func compare(_ a: [UInt8], _ b: [UInt8]) -> Int {
        for i in 0 ..< a.count where a[i] != b[i] { return a[i] < b[i] ? -1 : 1 }
        return 0
    }

    /// Trailing zero bits from the least-significant end; `8·len` when all-zero.
    static func trailingZeros(_ a: [UInt8]) -> Int {
        var count = 0
        for byte in a.reversed() {
            if byte == 0 { count += 8; continue }
            return count + byte.trailingZeroBitCount
        }
        return count
    }

    /// `a` with its lowest `n` bits set (equals `a + 2ⁿ − 1` when `a` is aligned).
    static func orLowBits(_ a: [UInt8], _ n: Int) -> [UInt8] {
        var r = a
        var bits = n, i = a.count - 1
        while bits > 0, i >= 0 {
            let take = min(8, bits)
            r[i] |= UInt8((1 << take) - 1)
            bits -= take; i -= 1
        }
        return r
    }

    /// `a + 2ⁿ`, big-endian, with an overflow flag when it leaves the width.
    static func addPow2(_ a: [UInt8], _ n: Int) -> (value: [UInt8], overflow: Bool) {
        var r = a
        var idx = a.count - 1 - (n / 8)
        guard idx >= 0 else { return (r, true) }
        var carry = UInt16(1) << (n % 8)
        while idx >= 0, carry > 0 {
            let sum = UInt16(r[idx]) + carry
            r[idx] = UInt8(sum & 0xFF)
            carry = sum >> 8
            idx -= 1
        }
        return (r, carry > 0)
    }

    // MARK: - address helpers

    static func isV4Mapped(_ b: [UInt8]) -> Bool {
        b.count == 16 && b[0 ..< 10].allSatisfy { $0 == 0 } && b[10] == 0xFF && b[11] == 0xFF
    }

    static func render(_ base: [UInt8], prefix: Int, v4: Bool) -> String {
        if v4 {
            return "\(base[0]).\(base[1]).\(base[2]).\(base[3])/\(prefix)"
        }
        var addr = in6_addr()
        withUnsafeMutableBytes(of: &addr) { $0.copyBytes(from: base) }
        var buf = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        inet_ntop(AF_INET6, &addr, &buf, socklen_t(INET6_ADDRSTRLEN))
        let text = buf.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return "\(String(decoding: text, as: UTF8.self))/\(prefix)"
    }
}
