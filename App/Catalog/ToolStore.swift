import SwiftUI
import Observation

/// App-wide catalog state: pinned tools and collapsed sections, persisted to disk.
@Observable
final class ToolStore {
    private(set) var pinnedIDs: [String]
    private var collapsedSectionIDs: Set<String>

    private let pinnedKey = "checknet.pinnedTools"
    private let collapsedKey = "checknet.collapsedSections"

    init() {
        let defaults = UserDefaults.standard
        pinnedIDs = defaults.stringArray(forKey: pinnedKey) ?? []
        collapsedSectionIDs = Set(defaults.stringArray(forKey: collapsedKey) ?? [])
    }

    func isPinned(_ tool: Tool) -> Bool { pinnedIDs.contains(tool.id) }

    func togglePin(_ tool: Tool) {
        if let idx = pinnedIDs.firstIndex(of: tool.id) {
            pinnedIDs.remove(at: idx)
        } else {
            pinnedIDs.append(tool.id)
        }
        persistPinned()
    }

    var pinnedTools: [Tool] {
        pinnedIDs.compactMap { Tool(rawValue: $0) }
    }

    func isCollapsed(_ section: ToolSection) -> Bool { collapsedSectionIDs.contains(section.id) }

    func toggleCollapse(_ section: ToolSection) {
        if collapsedSectionIDs.contains(section.id) {
            collapsedSectionIDs.remove(section.id)
        } else {
            collapsedSectionIDs.insert(section.id)
        }
        UserDefaults.standard.set(Array(collapsedSectionIDs), forKey: collapsedKey)
    }

    private func persistPinned() {
        UserDefaults.standard.set(pinnedIDs, forKey: pinnedKey)
    }
}
