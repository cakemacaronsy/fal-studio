import Foundation

/// A JSON-representable value, used both for building FAL request payloads
/// and for persisting the exact settings of each gallery item.
nonisolated enum JSONValue: Codable, Hashable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let v = try? container.decode(Bool.self) { self = .bool(v) }
        else if let v = try? container.decode(Int.self) { self = .int(v) }
        else if let v = try? container.decode(Double.self) { self = .double(v) }
        else if let v = try? container.decode(String.self) { self = .string(v) }
        else if let v = try? container.decode([JSONValue].self) { self = .array(v) }
        else if let v = try? container.decode([String: JSONValue].self) { self = .object(v) }
        else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .object(let v): try container.encode(v)
        case .null: try container.encodeNil()
        }
    }

    /// Human-readable form for the settings list in the detail sheet.
    var displayString: String {
        switch self {
        case .string(let v): return v
        case .int(let v): return String(v)
        case .double(let v): return String(v)
        case .bool(let v): return v ? "on" : "off"
        case .array(let v): return v.map(\.displayString).joined(separator: ", ")
        case .object(let v):
            return v.keys.sorted().map { "\($0): \(v[$0]!.displayString)" }.joined(separator: ", ")
        case .null:
            return "—"
        }
    }

    var stringValue: String? {
        if case .string(let v) = self { return v }
        return nil
    }

    var intValue: Int? {
        if case .int(let v) = self { return v }
        return nil
    }

    var boolValue: Bool? {
        if case .bool(let v) = self { return v }
        return nil
    }

    static func encodeToData(_ dict: [String: JSONValue]) throws -> Data {
        try JSONEncoder().encode(dict)
    }
}
