import Foundation

/// A saved host/target the user can quickly reuse, optionally scoped to a tool.
///
/// The model lives in `Shared/` so the QR import/export codec (`HostSharing`)
/// and its tests can build against it without pulling in the SwiftUI store.
struct SavedHost: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var value: String       // host or IP
    var toolID: String?     // nil = global favorite
}
