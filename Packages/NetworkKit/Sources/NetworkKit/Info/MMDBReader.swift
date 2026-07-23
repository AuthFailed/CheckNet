import Foundation
#if canImport(Glibc)
import Glibc
#endif

/// A minimal reader for the MaxMind DB (.mmdb) binary format — enough to look up
/// an IP in the GeoLite2 City and ASN databases offline. No dependency; the
/// format is a binary search tree over the address bits followed by a typed data
/// section (https://maxmind.github.io/MaxMind-DB/).
struct MMDBReader {
    private let bytes: [UInt8]
    private let nodeCount: Int
    private let recordSize: Int
    private let ipVersion: Int
    private let nodeByteSize: Int
    private let searchTreeSize: Int
    private let dataSectionStart: Int

    /// The value type decoded from the data section.
    indirect enum Value {
        case map([String: Value])
        case array([Value])
        case string(String)
        case double(Double)
        case float(Float)
        case uint(UInt64)
        case int(Int64)
        case bool(Bool)
        case bytes([UInt8])

        subscript(_ key: String) -> Value? {
            if case .map(let m) = self { return m[key] }
            return nil
        }
        var stringValue: String? { if case .string(let s) = self { return s } else { return nil } }
        var doubleValue: Double? {
            switch self {
            case .double(let d): return d
            case .float(let f): return Double(f)
            default: return nil
            }
        }
        var uintValue: UInt64? {
            switch self {
            case .uint(let u): return u
            case .int(let i) where i >= 0: return UInt64(i)
            default: return nil
            }
        }
        var arrayValue: [Value]? { if case .array(let a) = self { return a } else { return nil } }
    }

    init?(data: Data) {
        let bytes = [UInt8](data)
        // Metadata sits after the last "\xAB\xCD\xEFMaxMind.com" marker.
        let marker: [UInt8] = [0xAB, 0xCD, 0xEF] + Array("MaxMind.com".utf8)
        guard let markerStart = Self.lastRange(of: marker, in: bytes) else { return nil }
        let metadataStart = markerStart + marker.count
        let metaDecoder = Decoder(bytes: bytes, pointerBase: metadataStart)
        guard let (metaValue, _) = metaDecoder.decode(metadataStart),
              let nodeCount = metaValue["node_count"]?.uintValue,
              let recordSize = metaValue["record_size"]?.uintValue,
              let ipVersion = metaValue["ip_version"]?.uintValue else { return nil }

        self.bytes = bytes
        self.nodeCount = Int(nodeCount)
        self.recordSize = Int(recordSize)
        self.ipVersion = Int(ipVersion)
        self.nodeByteSize = Int(recordSize) * 2 / 8
        self.searchTreeSize = Int(nodeCount) * (Int(recordSize) * 2 / 8)
        self.dataSectionStart = searchTreeSize + 16
    }

    /// Look up an IP literal; returns its data-section value, or nil if the tree
    /// has no record for it.
    func lookup(ip: String) -> Value? {
        guard let addressBits = Self.addressBits(ip, dbVersion: ipVersion) else { return nil }
        var node = 0
        for bit in addressBits {
            if node >= nodeCount { break }
            node = record(node: node, right: bit)
            if node == nodeCount { return nil }         // explicit "no data"
            if node > nodeCount {                       // data pointer
                let offset = node - nodeCount + searchTreeSize
                let decoder = Decoder(bytes: bytes, pointerBase: dataSectionStart)
                return decoder.decode(offset)?.value
            }
        }
        return nil
    }

    // MARK: Tree

    private func record(node: Int, right: Bool) -> Int {
        let base = node * nodeByteSize
        switch recordSize {
        case 24:
            let off = base + (right ? 3 : 0)
            return Int(bytes[off]) << 16 | Int(bytes[off + 1]) << 8 | Int(bytes[off + 2])
        case 28:
            // 7-byte node; the middle byte (base+3) is split: its high nibble is
            // the left record's top bits, its low nibble the right record's.
            let middle = Int(bytes[base + 3])
            if right {
                return (middle & 0x0F) << 24 | Int(bytes[base + 4]) << 16
                     | Int(bytes[base + 5]) << 8 | Int(bytes[base + 6])
            } else {
                return ((middle & 0xF0) >> 4) << 24 | Int(bytes[base]) << 16
                     | Int(bytes[base + 1]) << 8 | Int(bytes[base + 2])
            }
        case 32:
            let off = base + (right ? 4 : 0)
            return Int(bytes[off]) << 24 | Int(bytes[off + 1]) << 16
                 | Int(bytes[off + 2]) << 8 | Int(bytes[off + 3])
        default:
            return nodeCount // treat as "no data"
        }
    }

    // MARK: Address → bits

    static func addressBits(_ ip: String, dbVersion: Int) -> [Bool]? {
        var v4 = in_addr()
        var v6 = in6_addr()
        if ip.withCString({ inet_pton(AF_INET, $0, &v4) }) == 1 {
            var addr = UInt32(bigEndian: v4.s_addr)
            var bits = (0..<32).map { _ -> Bool in defer { addr <<= 1 }; return (addr & 0x8000_0000) != 0 }
            // IPv4 in an IPv6 database lives under ::/96.
            if dbVersion == 6 { bits = Array(repeating: false, count: 96) + bits }
            return bits
        }
        if ip.withCString({ inet_pton(AF_INET6, $0, &v6) }) == 1 {
            let octets = withUnsafeBytes(of: v6) { Array($0.bindMemory(to: UInt8.self)) }
            return octets.flatMap { byte in (0..<8).map { (byte >> (7 - $0)) & 1 == 1 } }
        }
        return nil
    }

    private static func lastRange(of pattern: [UInt8], in data: [UInt8]) -> Int? {
        guard pattern.count <= data.count else { return nil }
        var i = data.count - pattern.count
        while i >= 0 {
            if Array(data[i..<i + pattern.count]) == pattern { return i }
            i -= 1
        }
        return nil
    }

    // MARK: Data-section decoder

    private struct Decoder {
        let bytes: [UInt8]
        /// File offset of the data section, for resolving pointers.
        let pointerBase: Int

        func decode(_ offset: Int) -> (value: Value, next: Int)? {
            guard offset < bytes.count else { return nil }
            let control = bytes[offset]
            var type = Int(control >> 5)
            var cursor = offset + 1
            if type == 0 { // extended type
                guard cursor < bytes.count else { return nil }
                type = Int(bytes[cursor]) + 7
                cursor += 1
            }
            if type == 1 { // pointer
                return decodePointer(control: control, cursor: cursor)
            }
            // Size.
            var size = Int(control & 0x1F)
            if size >= 29 {
                let extra = size - 28
                guard cursor + extra <= bytes.count else { return nil }
                var value = 0
                for _ in 0..<extra { value = value << 8 | Int(bytes[cursor]); cursor += 1 }
                switch extra {
                case 1: size = 29 + value
                case 2: size = 285 + value
                default: size = 65_821 + value
                }
            }
            return decodeValue(type: type, size: size, cursor: cursor)
        }

        private func decodePointer(control: UInt8, cursor: Int) -> (value: Value, next: Int)? {
            let pss = Int((control >> 3) & 0x3)
            let bytesToRead = pss + 1
            guard cursor + bytesToRead <= bytes.count else { return nil }
            var pointer = 0
            if pss < 3 { pointer = Int(control & 0x7) }
            for i in 0..<bytesToRead { pointer = pointer << 8 | Int(bytes[cursor + i]) }
            switch pss {
            case 1: pointer += 2048
            case 2: pointer += 526_336
            default: break
            }
            guard let resolved = decode(pointerBase + pointer) else { return nil }
            return (resolved.value, cursor + bytesToRead)
        }

        private func decodeValue(type: Int, size: Int, cursor: Int) -> (value: Value, next: Int)? {
            switch type {
            case 2: // utf8 string
                guard cursor + size <= bytes.count else { return nil }
                return (.string(String(decoding: bytes[cursor..<cursor + size], as: UTF8.self)), cursor + size)
            case 3: // double
                guard cursor + 8 <= bytes.count else { return nil }
                let bits = uint(cursor, 8)
                return (.double(Double(bitPattern: bits)), cursor + 8)
            case 4: // bytes
                guard cursor + size <= bytes.count else { return nil }
                return (.bytes(Array(bytes[cursor..<cursor + size])), cursor + size)
            case 5, 6, 9, 10: // uint16/32/64/128 (128 clamped to 64)
                guard cursor + size <= bytes.count else { return nil }
                return (.uint(uint(cursor, Swift.min(size, 8))), cursor + size)
            case 7: // map
                var map: [String: Value] = [:]
                var c = cursor
                for _ in 0..<size {
                    guard let (key, afterKey) = decode(c), case .string(let k) = key,
                          let (val, afterVal) = decode(afterKey) else { return nil }
                    map[k] = val
                    c = afterVal
                }
                return (.map(map), c)
            case 8: // int32
                guard cursor + size <= bytes.count else { return nil }
                let raw = uint(cursor, size)
                let value = Int64(Int32(bitPattern: UInt32(truncatingIfNeeded: raw)))
                return (.int(value), cursor + size)
            case 11: // array
                var array: [Value] = []
                var c = cursor
                for _ in 0..<size {
                    guard let (val, after) = decode(c) else { return nil }
                    array.append(val)
                    c = after
                }
                return (.array(array), c)
            case 14: // boolean
                return (.bool(size != 0), cursor)
            case 15: // float
                guard cursor + 4 <= bytes.count else { return nil }
                return (.float(Float(bitPattern: UInt32(truncatingIfNeeded: uint(cursor, 4)))), cursor + 4)
            default:
                return nil
            }
        }

        private func uint(_ offset: Int, _ count: Int) -> UInt64 {
            var value: UInt64 = 0
            for i in 0..<count { value = value << 8 | UInt64(bytes[offset + i]) }
            return value
        }
    }
}
