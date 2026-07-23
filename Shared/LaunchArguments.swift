import Foundation

/// Pure parser for the debug / deep-link launch arguments, e.g.
/// `CheckNet -openTool ping -host 1.1.1.1 -run`.
///
/// Kept free of the `Tool` enum so it can be unit-tested against arbitrary
/// argument vectors; the caller maps `toolRawValue` onto a real `Tool`.
enum LaunchArguments {
    struct Parsed: Equatable {
        var toolRawValue: String
        var host: String?
        var run: Bool
    }

    static func parse(_ args: [String]) -> Parsed? {
        guard let idx = args.firstIndex(of: "-openTool"), idx + 1 < args.count else { return nil }
        let tool = args[idx + 1]
        var host: String? = nil
        if let h = args.firstIndex(of: "-host"), h + 1 < args.count { host = args[h + 1] }
        return Parsed(toolRawValue: tool, host: host, run: args.contains("-run"))
    }
}
