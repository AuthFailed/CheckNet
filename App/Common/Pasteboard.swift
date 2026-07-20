import Foundation
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Thin cross-platform wrapper over the system pasteboard.
enum Pasteboard {
    static var string: String? {
        #if os(iOS)
        UIPasteboard.general.string
        #else
        NSPasteboard.general.string(forType: .string)
        #endif
    }

    static func copy(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}
