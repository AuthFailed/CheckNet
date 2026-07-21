import Foundation

/// A single value a tool can put in a webhook, carrying its type so it can be
/// encoded correctly for each format (a number stays a number, a date becomes
/// ISO-8601, a bool stays a bool).
public indirect enum WebhookValue: Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case date(Date)
    /// An ordered list of sub-objects (e.g. per-probe ping samples).
    case objects([[String: WebhookValue]])
    case null
}

/// Describes one field a tool can emit: a stable key, a human label, whether it
/// is on by default, and — for list fields — the sub-fields of each element.
public struct WebhookField: Sendable, Hashable, Identifiable {
    public let key: String
    public let label: String
    public let defaultOn: Bool
    /// Sub-fields, for a field whose value is a list of objects.
    public let children: [WebhookField]

    public var id: String { key }

    public init(_ key: String, _ label: String, defaultOn: Bool = true, children: [WebhookField] = []) {
        self.key = key
        self.label = label
        self.defaultOn = defaultOn
        self.children = children
    }

    public var isList: Bool { !children.isEmpty }
}

/// Everything a tool exposes to webhooks: the ordered field descriptors and, for
/// a given result, the values behind them.
public struct WebhookSchema: Sendable {
    public let toolKey: String
    public let toolLabel: String
    public let fields: [WebhookField]

    public init(toolKey: String, toolLabel: String, fields: [WebhookField]) {
        self.toolKey = toolKey
        self.toolLabel = toolLabel
        self.fields = fields
    }

    /// Every selectable path, including nested `parent.child` paths. Used to seed
    /// a default (all-on) selection.
    public var allPaths: [String] {
        fields.flatMap { field -> [String] in
            [field.key] + field.children.map { "\(field.key).\($0.key)" }
        }
    }

    public var defaultPaths: Set<String> {
        var paths = Set<String>()
        for field in fields where field.defaultOn {
            paths.insert(field.key)
            for child in field.children where child.defaultOn {
                paths.insert("\(field.key).\(child.key)")
            }
        }
        return paths
    }
}

/// The wire format for the payload.
public enum WebhookFormat: String, Sendable, CaseIterable, Codable, Identifiable {
    /// Nested JSON — the native shape, values keep their structure.
    case jsonNested
    /// Flat JSON — nested lists are flattened to `key.0.subkey` style keys.
    case jsonFlat
    /// `application/x-www-form-urlencoded`, for endpoints that expect a form.
    case formURLEncoded

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .jsonNested: "JSON (вложенный)"
        case .jsonFlat: "JSON (плоский)"
        case .formURLEncoded: "Form URL-encoded"
        }
    }

    public var contentType: String {
        switch self {
        case .jsonNested, .jsonFlat: "application/json"
        case .formURLEncoded: "application/x-www-form-urlencoded"
        }
    }
}

/// Builds the request body from a tool's values, the user's field selection and
/// the chosen format.
///
/// The whole point is that the user decides which of a tool's *available* fields
/// go out — everything is on by default so it works natively, but any field, and
/// any sub-field of an intermediate list, can be dropped.
public enum WebhookPayloadBuilder {
    /// A fresh formatter per call — cheap, and avoids sharing mutable state
    /// across the concurrent contexts that build payloads.
    private static func isoString(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    /// Produces the encoded body and its Content-Type.
    public static func build(
        schema: WebhookSchema,
        values: [String: WebhookValue],
        selected: Set<String>,
        envelope: [String: WebhookValue] = [:],
        format: WebhookFormat
    ) -> (body: Data, contentType: String) {
        // Ordered (key, value) pairs, filtered by the selection and the schema order.
        var ordered: [(String, WebhookValue)] = []
        for (key, value) in envelope.sorted(by: { $0.key < $1.key }) {
            ordered.append((key, value))
        }
        for field in schema.fields where selected.contains(field.key) {
            guard let value = values[field.key] else { continue }
            ordered.append((field.key, filter(value, field: field, selected: selected)))
        }

        switch format {
        case .jsonNested:
            return (encodeJSON(ordered, flatten: false), format.contentType)
        case .jsonFlat:
            return (encodeJSON(ordered, flatten: true), format.contentType)
        case .formURLEncoded:
            return (encodeForm(ordered), format.contentType)
        }
    }

    /// Drops unselected sub-fields from a list value.
    private static func filter(_ value: WebhookValue, field: WebhookField, selected: Set<String>) -> WebhookValue {
        guard case .objects(let items) = value, field.isList else { return value }
        let keepKeys = Set(field.children
            .filter { selected.contains("\(field.key).\($0.key)") }
            .map(\.key))
        let filtered = items.map { item in
            item.filter { keepKeys.contains($0.key) }
        }
        return .objects(filtered)
    }

    // MARK: - JSON

    private static func encodeJSON(_ pairs: [(String, WebhookValue)], flatten: Bool) -> Data {
        var object: [String: Any] = [:]
        for (key, value) in pairs {
            if flatten {
                flattenInto(&object, prefix: key, value: value)
            } else {
                object[key] = jsonObject(value)
            }
        }
        // sortedKeys keeps the signature stable; the caller signs these bytes.
        return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
    }

    private static func jsonObject(_ value: WebhookValue) -> Any {
        switch value {
        case .string(let s): return s
        case .int(let i): return i
        case .double(let d): return d
        case .bool(let b): return b
        case .date(let d): return isoString(d)
        case .null: return NSNull()
        case .objects(let items):
            return items.map { item in item.mapValues { jsonObject($0) } }
        }
    }

    private static func flattenInto(_ object: inout [String: Any], prefix: String, value: WebhookValue) {
        switch value {
        case .objects(let items):
            for (index, item) in items.enumerated() {
                for (subkey, subvalue) in item {
                    flattenInto(&object, prefix: "\(prefix).\(index).\(subkey)", value: subvalue)
                }
            }
        default:
            object[prefix] = jsonObject(value)
        }
    }

    // MARK: - Form URL encoded

    private static func encodeForm(_ pairs: [(String, WebhookValue)]) -> Data {
        var parts: [String] = []
        for (key, value) in pairs {
            appendForm(&parts, key: key, value: value)
        }
        return Data(parts.joined(separator: "&").utf8)
    }

    private static func appendForm(_ parts: inout [String], key: String, value: WebhookValue) {
        switch value {
        case .objects(let items):
            for (index, item) in items.enumerated() {
                for (subkey, subvalue) in item.sorted(by: { $0.key < $1.key }) {
                    appendForm(&parts, key: "\(key)[\(index)][\(subkey)]", value: subvalue)
                }
            }
        case .null:
            parts.append("\(escape(key))=")
        default:
            parts.append("\(escape(key))=\(escape(scalarString(value)))")
        }
    }

    private static func scalarString(_ value: WebhookValue) -> String {
        switch value {
        case .string(let s): return s
        case .int(let i): return String(i)
        case .double(let d): return String(d)
        case .bool(let b): return b ? "true" : "false"
        case .date(let d): return isoString(d)
        case .null, .objects: return ""
        }
    }

    private static func escape(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
}
