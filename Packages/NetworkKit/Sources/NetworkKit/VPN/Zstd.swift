import Foundation
import CZstd

/// Thin Swift front for the vendored decompress-only Zstandard core. Apple's
/// `Compression` framework speaks LZFSE/LZ4/zlib/LZMA but not zstd, which is what
/// mihomo `.mrs` rule-sets are wrapped in — hence the small C dependency.
public enum Zstd {
    public enum Failure: Error, Equatable, Sendable { case notZstd, corrupt, tooLarge }

    /// The 4-byte zstd frame magic (little-endian 0xFD2FB528).
    static let magic: [UInt8] = [0x28, 0xB5, 0x2F, 0xFD]

    /// Decompress a whole zstd frame. Uses the size baked into the frame header
    /// when present, otherwise streams into a growing buffer. `sizeLimit` guards
    /// against a hostile frame claiming a huge output.
    public static func decompress(_ data: Data, sizeLimit: Int = 256 << 20) throws -> Data {
        guard data.count >= 4 else { throw Failure.notZstd }
        return try data.withUnsafeBytes { raw -> Data in
            guard let src = raw.baseAddress, raw.count >= 4,
                  memcmp(src, magic, 4) == 0 else { throw Failure.notZstd }

            let declared = ZSTD_getFrameContentSize(src, raw.count)
            if declared != ZSTD_CONTENTSIZE_UNKNOWN && declared != ZSTD_CONTENTSIZE_ERROR {
                guard declared <= UInt64(sizeLimit) else { throw Failure.tooLarge }
                var out = Data(count: Int(declared))
                let written = out.withUnsafeMutableBytes { dst in
                    ZSTD_decompress(dst.baseAddress, dst.count, src, raw.count)
                }
                guard ZSTD_isError(written) == 0 else { throw Failure.corrupt }
                if written != out.count { out.removeSubrange(Int(written)..<out.count) }
                return out
            }
            return try stream(src: src, count: raw.count, sizeLimit: sizeLimit)
        }
    }

    /// Streaming path for frames without a declared content size.
    private static func stream(src: UnsafeRawPointer, count: Int, sizeLimit: Int) throws -> Data {
        guard let dctx = ZSTD_createDCtx() else { throw Failure.corrupt }
        defer { ZSTD_freeDCtx(dctx) }
        var out = Data()
        var chunk = [UInt8](repeating: 0, count: max(1, ZSTD_DStreamOutSize()))
        var input = ZSTD_inBuffer(src: src, size: count, pos: 0)
        while input.pos < input.size {
            let finished = try chunk.withUnsafeMutableBytes { buf -> Bool in
                var output = ZSTD_outBuffer(dst: buf.baseAddress, size: buf.count, pos: 0)
                let ret = ZSTD_decompressStream(dctx, &output, &input)
                guard ZSTD_isError(ret) == 0 else { throw Failure.corrupt }
                if output.pos > 0 {
                    out.append(buf.baseAddress!.assumingMemoryBound(to: UInt8.self), count: output.pos)
                }
                guard out.count <= sizeLimit else { throw Failure.tooLarge }
                return ret == 0
            }
            if finished { break }
        }
        return out
    }
}
