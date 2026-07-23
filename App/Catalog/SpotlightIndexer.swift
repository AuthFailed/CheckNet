import Foundation
import CoreSpotlight
import UniformTypeIdentifiers
import os

/// Indexes the tool catalogue into Spotlight so a search for "ping", "DNS",
/// "скорость" etc. surfaces the tool and opens straight to it. The identifier
/// is the tool's raw value, which `ToolNavigator` turns back into a route.
enum SpotlightIndexer {
    static let domain = "com.chrsnv.checknet.tools"

    /// Identifier attached to a tapped result's user activity.
    static func tool(from activity: NSUserActivity) -> Tool? {
        guard activity.activityType == CSSearchableItemActionType,
              let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return nil }
        return Tool(rawValue: id)
    }

    /// (Re)index the catalogue's tools. Cheap; safe to call on every launch.
    static func index() {
        let tools = ToolCatalog.sections.flatMap(\.tools)
        let items = tools.map { tool -> CSSearchableItem in
            let attributes = CSSearchableItemAttributeSet(contentType: .text)
            attributes.title = localized(tool.title)
            attributes.contentDescription = localized(tool.subtitle)
            // Match on synonyms plus the visible title/subtitle words.
            attributes.keywords = tool.keywords + [localized(tool.title), localized(tool.subtitle)]
            return CSSearchableItem(uniqueIdentifier: tool.rawValue,
                                    domainIdentifier: domain, attributeSet: attributes)
        }
        let log = Logger(subsystem: "com.chrsnv.checknet", category: "spotlight")
        CSSearchableIndex.default().indexSearchableItems(items) { error in
            if let error {
                log.error("index failed: \(error.localizedDescription, privacy: .public)")
            } else {
                log.log("indexed \(items.count, privacy: .public) tools")
            }
        }
    }

    /// Tool strings are Russian literals acting as catalog keys; resolve them so
    /// Spotlight shows text in the app's language.
    private static func localized(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }
}
