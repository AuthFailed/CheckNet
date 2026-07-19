import Foundation

/// Reads the system ARP cache (IPv4 → MAC) via `sysctl(NET_RT_FLAGS)`.
/// Populated by prior traffic (e.g. a ping sweep). Availability is best-effort:
/// full on macOS, partial/empty on locked-down iOS.
enum ARPTable {
    #if os(macOS)
    static func entries() -> [String: String] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_FLAGS, RTF_LLINFO]
        var needed = 0
        guard sysctl(&mib, u_int(mib.count), nil, &needed, nil, 0) == 0, needed > 0 else { return [:] }

        var buffer = [UInt8](repeating: 0, count: needed)
        guard sysctl(&mib, u_int(mib.count), &buffer, &needed, nil, 0) == 0 else { return [:] }

        var result: [String: String] = [:]
        buffer.withUnsafeBytes { raw in
            var offset = 0
            let base = raw.baseAddress!
            while offset < needed {
                let rtm = base.advanced(by: offset).assumingMemoryBound(to: rt_msghdr2.self)
                let msgLen = Int(rtm.pointee.rtm_msglen)
                if msgLen == 0 { break }

                // sockaddr_inarp (dst) immediately follows the header, then sockaddr_dl (gateway/MAC).
                let sinPtr = base.advanced(by: offset + MemoryLayout<rt_msghdr2>.size)
                    .assumingMemoryBound(to: sockaddr_in.self)
                let sdlOffset = offset + MemoryLayout<rt_msghdr2>.size + Int(roundUp(sinPtr.pointee.sin_len))
                if sdlOffset + MemoryLayout<sockaddr_dl>.size <= needed {
                    let sdlPtr = base.advanced(by: sdlOffset).assumingMemoryBound(to: sockaddr_dl.self)
                    if let mac = macString(sdlPtr) {
                        let ip = ipString(sinPtr.pointee.sin_addr)
                        result[ip] = mac
                    }
                }
                offset += msgLen
            }
        }
        return result
    }

    #else
    /// iOS restricts access to the ARP/route table; MAC discovery is unavailable.
    static func entries() -> [String: String] { [:] }
    #endif

    private static func roundUp(_ len: UInt8) -> Int {
        let l = Int(len)
        return l == 0 ? 4 : (l + 3) & ~3
    }

    private static func ipString(_ addr: in_addr) -> String {
        let a = addr.s_addr
        return "\(a & 0xFF).\((a >> 8) & 0xFF).\((a >> 16) & 0xFF).\((a >> 24) & 0xFF)"
    }

    private static func macString(_ sdl: UnsafePointer<sockaddr_dl>) -> String? {
        let len = Int(sdl.pointee.sdl_alen)
        guard len == 6 else { return nil }
        // The link-layer address starts at sdl_data + sdl_nlen.
        let nlen = Int(sdl.pointee.sdl_nlen)
        return withUnsafePointer(to: sdl.pointee.sdl_data) { dataPtr in
            dataPtr.withMemoryRebound(to: UInt8.self, capacity: nlen + len) { bytes in
                var mac = [String]()
                for i in 0..<6 { mac.append(String(format: "%02X", bytes[nlen + i])) }
                let joined = mac.joined(separator: ":")
                return joined == "00:00:00:00:00:00" ? nil : joined
            }
        }
    }
}
