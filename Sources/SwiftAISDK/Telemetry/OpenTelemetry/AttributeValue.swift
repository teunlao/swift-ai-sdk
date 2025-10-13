import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 OpenTelemetry attribute value types.

 Minimal abstraction of OpenTelemetry API types for telemetry support.
 Port of `@opentelemetry/api` AttributeValue types.

 This allows telemetry functionality without requiring OpenTelemetry SDK dependency.
 Users can bridge these to real OpenTelemetry types if needed.
 */

/// OpenTelemetry attribute value (primitive or array of primitives)
public enum AttributeValue: Sendable, Equatable, Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case stringArray([String])
    case intArray([Int])
    case doubleArray([Double])
    case boolArray([Bool])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode([String].self) {
            self = .stringArray(value)
        } else if let value = try? container.decode([Int].self) {
            self = .intArray(value)
        } else if let value = try? container.decode([Double].self) {
            self = .doubleArray(value)
        } else if let value = try? container.decode([Bool].self) {
            self = .boolArray(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported attribute value type"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .stringArray(let value): try container.encode(value)
        case .intArray(let value): try container.encode(value)
        case .doubleArray(let value): try container.encode(value)
        case .boolArray(let value): try container.encode(value)
        }
    }
}

/// OpenTelemetry attributes (key-value pairs)
public typealias Attributes = [String: AttributeValue]

// MARK: - Convenience Initializers

extension AttributeValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = .string(value)
    }
}

extension AttributeValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self = .int(value)
    }
}

extension AttributeValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self = .double(value)
    }
}

extension AttributeValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        self = .bool(value)
    }
}

extension AttributeValue: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: String...) {
        self = .stringArray(elements)
    }
}
