import Foundation

/// Monotonic clock helpers, immune to wall-clock adjustments.
enum MonoClock {
    static func nanos() -> UInt64 {
        var ts = timespec()
        clock_gettime(CLOCK_MONOTONIC_RAW, &ts)
        return UInt64(ts.tv_sec) &* 1_000_000_000 &+ UInt64(ts.tv_nsec)
    }
    /// Milliseconds elapsed since a prior `nanos()` reading.
    static func millisSince(_ start: UInt64) -> Double {
        Double(nanos() &- start) / 1_000_000.0
    }
}
