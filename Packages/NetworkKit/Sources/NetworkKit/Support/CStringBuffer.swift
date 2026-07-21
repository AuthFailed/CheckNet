import Foundation

extension String {
    /// Decodes a null-terminated C string out of a fixed-size `[CChar]` buffer.
    ///
    /// The POSIX name-resolution calls write into a buffer sized for the worst
    /// case and leave the remainder zeroed. `String(cString:)` did this, but its
    /// array overload is deprecated: it cannot tell a buffer from a sequence of
    /// bytes, so the caller has to say where the string ends. Everything from the
    /// first NUL onwards is padding.
    init(nullTerminated buffer: [CChar]) {
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        self = String(decoding: bytes, as: UTF8.self)
    }
}
