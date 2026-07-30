/*
 * Minimal public surface of the vendored single-file Zstandard decompressor
 * (zstddeclib.c, decompress-only amalgamation of facebook/zstd, BSD-licensed).
 * Only the entry points the .mrs viewer needs are declared here; the struct
 * tags match zstd.h so the ABI is identical.
 */
#ifndef CZSTD_H
#define CZSTD_H

#include <stddef.h>

/* One-shot decompression (used when the frame carries its content size). */
size_t ZSTD_decompress(void* dst, size_t dstCapacity, const void* src, size_t compressedSize);

/* Decompressed size baked into the frame header, or the sentinels below. */
unsigned long long ZSTD_getFrameContentSize(const void* src, size_t srcSize);
#define ZSTD_CONTENTSIZE_UNKNOWN (0ULL - 1)
#define ZSTD_CONTENTSIZE_ERROR   (0ULL - 2)

/* Non-zero when a returned size_t is actually an error code. */
unsigned ZSTD_isError(size_t code);

/* Streaming decompression — the fallback when the size is not known up front. */
typedef struct ZSTD_DCtx_s ZSTD_DCtx;
ZSTD_DCtx* ZSTD_createDCtx(void);
size_t     ZSTD_freeDCtx(ZSTD_DCtx* dctx);

typedef struct ZSTD_inBuffer_s  { const void* src; size_t size; size_t pos; } ZSTD_inBuffer;
typedef struct ZSTD_outBuffer_s { void*       dst; size_t size; size_t pos; } ZSTD_outBuffer;
size_t ZSTD_decompressStream(ZSTD_DCtx* zds, ZSTD_outBuffer* output, ZSTD_inBuffer* input);
size_t ZSTD_DStreamOutSize(void);

#endif /* CZSTD_H */
