import Foundation

/// A property value the collector accepts: short strings, numbers, and booleans.
public enum RouteRevValue: Sendable, Equatable, Codable,
    ExpressibleByStringLiteral, ExpressibleByIntegerLiteral,
    ExpressibleByFloatLiteral, ExpressibleByBooleanLiteral {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)

    public init(stringLiteral value: String) { self = .string(value) }
    public init(integerLiteral value: Int) { self = .int(value) }
    public init(floatLiteral value: Double) { self = .double(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v.isFinite ? v : 0)
        case .bool(let v): try container.encode(v)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(Bool.self) { self = .bool(v) }
        else if let v = try? container.decode(Int.self) { self = .int(v) }
        else if let v = try? container.decode(Double.self) { self = .double(v) }
        else { self = .string(try container.decode(String.self)) }
    }
}

/// Wire format for one event. Field names and limits match the collector's schema
/// (routerev: src/features/ingest/ingest.schema.ts); anything over a limit is trimmed here
/// because the collector rejects the whole batch on an invalid event.
struct Event: Codable, Equatable, Sendable {
    let id: String
    let type: String
    let name: String?
    let ts: String
    let platform: String
    let visitorId: String
    let sessionId: String
    let userId: String?
    let url: String?
    let screenWidth: Int?
    let language: String?
    let timezone: String?
    let appVersion: String?
    let props: [String: RouteRevValue]?

    enum Kind: String {
        case screen, goal, identify
    }

    static func sanitize(_ props: [String: RouteRevValue]) -> [String: RouteRevValue]? {
        guard !props.isEmpty else { return nil }
        var result: [String: RouteRevValue] = [:]
        for key in props.keys.sorted().prefix(20) {
            guard let value = props[key] else { continue }
            if case .string(let s) = value {
                result[String(key.prefix(64))] = .string(String(s.prefix(500)))
            } else {
                result[String(key.prefix(64))] = value
            }
        }
        return result
    }

    static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

struct Batch: Encodable {
    let key: String
    let events: [Event]
}
