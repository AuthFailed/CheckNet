import Foundation

/// The domain payload of a `.mrs` file: a succinct LOUDS trie of domain rules,
/// stored reversed (so `com.example` groups by TLD). This is a faithful port of
/// mihomo's `component/trie` DomainSet reader and its `keys()` walk, with
/// popcount-based rank/select over `labelBitmap` in place of the precomputed
/// index tables (we only need to enumerate, once, for display).
struct SuccinctDomainSet {
    let leaves: [UInt64]
    let labelBitmap: [UInt64]
    let labels: [UInt8]
    /// prefix[k] = number of set bits in labelBitmap[0..<k]; enables O(1) rank.
    private let onesPrefix: [Int]

    init(leaves: [UInt64], labelBitmap: [UInt64], labels: [UInt8]) {
        self.leaves = leaves
        self.labelBitmap = labelBitmap
        self.labels = labels
        var prefix = [Int](repeating: 0, count: labelBitmap.count + 1)
        for i in 0 ..< labelBitmap.count { prefix[i + 1] = prefix[i] + labelBitmap[i].nonzeroBitCount }
        onesPrefix = prefix
    }

    /// version(1) · leaves(len+uint64s) · labelBitmap(len+uint64s) · labels(len+bytes)
    static func read(_ r: inout ByteReader) throws -> SuccinctDomainSet {
        let version = try r.u8()
        guard version == 1 else { throw MRSParser.ParseError.badVersion }
        let leaves = try r.u64Array()
        let labelBitmap = try r.u64Array()
        let labelsLen = try r.i64()
        guard labelsLen >= 0, labelsLen <= Int64(r.remaining) else { throw MRSParser.ParseError.truncated }
        let labels = Array(try r.take(Int(labelsLen)))
        return SuccinctDomainSet(leaves: leaves, labelBitmap: labelBitmap, labels: labels)
    }

    // MARK: - succinct bit ops

    private func bit(_ bm: [UInt64], _ i: Int) -> Bool {
        let w = i >> 6
        guard w >= 0, w < bm.count else { return false }
        return (bm[w] >> UInt64(i & 63)) & 1 != 0
    }

    /// Number of set bits in labelBitmap[0..<i].
    private func rank1(_ i: Int) -> Int {
        let w = i >> 6, b = i & 63
        var r = onesPrefix[min(w, onesPrefix.count - 1)]
        if b != 0, w < labelBitmap.count {
            r += (labelBitmap[w] & ((UInt64(1) << UInt64(b)) - 1)).nonzeroBitCount
        }
        return r
    }

    /// Index of the (k+1)-th set bit (0-indexed k), matching mihomo's selectIthOne.
    private func select1(_ k: Int) -> Int {
        var lo = 0, hi = labelBitmap.count
        while lo < hi {                                   // largest word with onesPrefix[w] <= k
            let mid = (lo + hi) / 2
            if onesPrefix[mid + 1] <= k { lo = mid + 1 } else { hi = mid }
        }
        guard lo < labelBitmap.count else { return lo << 6 }
        var word = labelBitmap[lo]
        var within = k - onesPrefix[lo]
        while within > 0 { word &= word - 1; within -= 1 } // drop the lowest set bits
        return (lo << 6) + word.trailingZeroBitCount
    }

    // MARK: - enumeration

    /// Every domain rule, in the form mihomo would match on (un-reversed). Direct
    /// port of mihomo's recursive `keys()` walk; recursion depth is bounded by the
    /// domain length (≤ 253 bytes), so it can't blow the stack. `limit` caps very
    /// large sets. Bounds are re-checked so a malformed file can't crash us.
    func domains(limit: Int = .max) -> [String] {
        guard !labelBitmap.isEmpty else { return [] }
        let bitCount = labelBitmap.count << 6
        var result: [String] = []
        var key: [UInt8] = []
        var stop = false

        func traverse(_ nodeId: Int, _ start: Int) {
            if bit(leaves, nodeId) {
                result.append(reversed(key))
                if result.count >= limit { stop = true; return }
            }
            var bmIdx = start
            while bmIdx < bitCount, !bit(labelBitmap, bmIdx) {
                let labelIdx = bmIdx - nodeId
                guard labelIdx >= 0, labelIdx < labels.count else { return }
                key.append(labels[labelIdx])
                let childNode = (bmIdx + 1) - rank1(bmIdx + 1)
                traverse(childNode, select1(childNode - 1) + 1)
                key.removeLast()
                if stop { return }
                bmIdx += 1
            }
        }
        traverse(0, 0)
        return result
    }

    private func reversed(_ key: [UInt8]) -> String {
        String(decoding: key.reversed(), as: UTF8.self)
    }
}
