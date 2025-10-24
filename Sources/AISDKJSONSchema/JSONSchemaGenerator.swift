import Foundation
import AISDKProvider
import AISDKProviderUtils

public enum JSONSchemaGenerator {
    private static let cacheBox = SchemaCache()

    public static func generate<T: Codable & Sendable>(for type: T.Type) -> JSONValue {
        let key = ObjectIdentifier(type)

        cacheBox.lock.lock()
        if let cached = cacheBox.storage[key] {
            cacheBox.lock.unlock()
            return cached
        }
        cacheBox.lock.unlock()

        let schema = resolveSchema(for: type) ?? JSONValue.object([
            "type": .string("object"),
            "additionalProperties": .bool(true)
        ])

        cacheBox.lock.lock()
        cacheBox.storage[key] = schema
        cacheBox.lock.unlock()

        return schema
    }
}

private extension JSONSchemaGenerator {
    static func resolveSchema<T: Codable & Sendable>(for type: T.Type) -> JSONValue? {
        do {
            let sample = try DefaultValueFactory.make(type)
            return try buildJSONSchema(from: sample)
        } catch {
            return nil
        }
    }

    static func buildJSONSchema<T>(from value: T) throws -> JSONValue {
        let mirror = Mirror(reflecting: value)
        var properties: [String: JSONValue] = [:]
        var required: [String] = []

        for child in mirror.children {
            guard let label = child.label else { continue }

            let propertyType = try inferJSONSchemaType(from: child.value)
            properties[label] = propertyType

            // Check if optional by trying to unwrap
            let isOptional = Mirror(reflecting: child.value).displayStyle == .optional
            if !isOptional {
                required.append(label)
            }
        }

        var schema: [String: JSONValue] = [
            "type": .string("object"),
            "properties": .object(properties)
        ]

        if !required.isEmpty {
            schema["required"] = .array(required.map { .string($0) })
        }

        return .object(schema)
    }

    static func inferJSONSchemaType(from value: Any) throws -> JSONValue {
        // Handle optionals by unwrapping
        if let optional = value as? any OptionalProtocol {
            if let wrapped = optional.wrappedValue {
                return try inferJSONSchemaType(from: wrapped)
            } else {
                // nil optional - infer from type
                return .object(["type": .string("object"), "additionalProperties": .bool(true)])
            }
        }

        // Primitive types
        if value is String {
            return .object(["type": .string("string")])
        }
        if value is Int || value is Int8 || value is Int16 || value is Int32 || value is Int64 ||
           value is UInt || value is UInt8 || value is UInt16 || value is UInt32 || value is UInt64 {
            return .object(["type": .string("integer")])
        }
        if value is Double || value is Float || value is Decimal {
            return .object(["type": .string("number")])
        }
        if value is Bool {
            return .object(["type": .string("boolean")])
        }

        // Foundation types
        if value is Date {
            return .object([
                "type": .string("string"),
                "format": .string("date-time")
            ])
        }
        if value is Data {
            return .object([
                "type": .string("string"),
                "format": .string("binary")
            ])
        }
        if value is URL {
            return .object([
                "type": .string("string"),
                "format": .string("uri")
            ])
        }

        // Enum types
        if let enumType = Swift.type(of: value) as? any CaseIterable.Type {
            return try buildEnumSchema(for: enumType, value: value)
        }

        // Array types
        if let arrayValue = value as? [Any] {
            return try buildArraySchema(from: arrayValue)
        }

        // Nested objects - recursively generate schema
        return try buildJSONSchema(from: value)
    }

    static func buildEnumSchema(for enumType: any CaseIterable.Type, value: Any) throws -> JSONValue {
        let mirror = Mirror(reflecting: enumType.allCases)
        let cases = mirror.children.compactMap { child -> JSONValue? in
            // Try to encode the case value
            if let stringValue = child.value as? any RawRepresentable<String> {
                return .string(stringValue.rawValue)
            }
            if let intValue = child.value as? any RawRepresentable<Int> {
                return .number(Double(intValue.rawValue))
            }
            // Use string representation as fallback
            return .string(String(describing: child.value))
        }

        // Determine base type from the value
        let baseType: String
        if value is any RawRepresentable<String> {
            baseType = "string"
        } else if value is any RawRepresentable<Int> {
            baseType = "integer"
        } else {
            baseType = "string"
        }

        return .object([
            "type": .string(baseType),
            "enum": .array(cases)
        ])
    }

    static func buildArraySchema(from array: [Any]) throws -> JSONValue {
        guard let first = array.first else {
            // Empty array - return generic array schema
            return .object([
                "type": .string("array"),
                "items": .object(["type": .string("object")])
            ])
        }

        let itemSchema = try inferJSONSchemaType(from: first)
        return .object([
            "type": .string("array"),
            "items": itemSchema
        ])
    }
}

private protocol OptionalProtocol {
    var wrappedValue: Any? { get }
}

extension Optional: OptionalProtocol {
    var wrappedValue: Any? {
        switch self {
        case .some(let value): return value
        case .none: return nil
        }
    }
}

private final class SchemaCache: @unchecked Sendable {
    let lock = NSLock()
    var storage: [ObjectIdentifier: JSONValue] = [:]
}
