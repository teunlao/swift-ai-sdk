import Foundation
import AISDKProvider

// MARK: - Options & Result Types

public struct ParseJSONOptions: Sendable {
    public let text: String

    public init(text: String) {
        self.text = text
    }
}

public struct ParseJSONWithSchemaOptions<Output>: Sendable {
    public let text: String
    public let schema: FlexibleSchema<Output>

    public init(text: String, schema: FlexibleSchema<Output>) {
        self.text = text
        self.schema = schema
    }
}

public enum ParseJSONResult<Output>: @unchecked Sendable {
    case success(value: Output, rawValue: Any)
    case failure(error: Error, rawValue: Any?)
}

// MARK: - parseJSON

/// Parses JSON text without applying a schema.
///
/// Port of `@ai-sdk/provider-utils/src/parse-json.ts`
public func parseJSON(
    _ options: ParseJSONOptions
) async throws -> JSONValue {
    do {
        let rawValue = try secureJsonParse(options.text)
        return try jsonValue(from: rawValue)
    } catch {
        if error is JSONParseError || error is TypeValidationError {
            throw error
        }
        throw JSONParseError(text: options.text, cause: error)
    }
}

/// Parses JSON text and validates it against a schema.
///
/// Port of `@ai-sdk/provider-utils/src/parse-json.ts`
public func parseJSON<Output>(
    _ options: ParseJSONWithSchemaOptions<Output>
) async throws -> Output {
    do {
        let rawValue = try secureJsonParse(options.text)
        return try await validateTypes(
            ValidateTypesOptions(value: rawValue, schema: options.schema)
        )
    } catch {
        if error is JSONParseError || error is TypeValidationError {
            throw error
        }
        throw JSONParseError(text: options.text, cause: error)
    }
}

// MARK: - safeParseJSON

/// Safely parses JSON text without applying a schema.
public func safeParseJSON(
    _ options: ParseJSONOptions
) async -> ParseJSONResult<JSONValue> {
    do {
        let rawValue = try secureJsonParse(options.text)
        let jsonValue = try jsonValue(from: rawValue)
        return .success(value: jsonValue, rawValue: rawValue)
    } catch {
        let wrapped = wrapJSONParseError(text: options.text, error: error)
        return .failure(error: wrapped, rawValue: nil)
    }
}

/// Safely parses JSON text with schema validation.
public func safeParseJSON<Output>(
    _ options: ParseJSONWithSchemaOptions<Output>
) async -> ParseJSONResult<Output> {
    do {
        let rawValue = try secureJsonParse(options.text)
        let validation = await safeValidateTypes(
            ValidateTypesOptions(value: rawValue, schema: options.schema)
        )

        switch validation {
        case .success(let value, let raw):
            return .success(value: value, rawValue: raw)
        case .failure(let error, let raw):
            return .failure(error: error, rawValue: raw)
        }
    } catch {
        let wrapped = wrapJSONParseError(text: options.text, error: error)
        return .failure(error: wrapped, rawValue: nil)
    }
}

// MARK: - Helpers

public func isParsableJson(_ text: String) -> Bool {
    do {
        _ = try secureJsonParse(text)
        return true
    } catch {
        return false
    }
}

private func wrapJSONParseError(text: String, error: Error) -> Error {
    if error is JSONParseError {
        return error
    }
    return JSONParseError(text: text, cause: error)
}

private func jsonValue(from value: Any) throws -> JSONValue {
    if let jsonValue = value as? JSONValue {
        return jsonValue
    }

    if value is NSNull {
        return .null
    }

    // CRITICAL FIX: Check NSNumber BEFORE Bool to avoid NSNumber(0)/NSNumber(1) coercion
    // See validation report: parsejson-bool-coercion-investigation-2025-10-12.md
    if let number = value as? NSNumber {
        // Detect actual JSON booleans using CFBoolean type check
        // JSONSerialization returns __NSCFBoolean for true/false, __NSCFNumber for numbers
        if CFGetTypeID(number as CFTypeRef) == CFBooleanGetTypeID() {
            return .bool(number.boolValue)
        }
        return .number(number.doubleValue)
    }

    // This check now only catches non-NSNumber Bool values (rare edge case)
    if let bool = value as? Bool {
        return .bool(bool)
    }

    if let dictionary = value as? [String: Any] {
        var result: [String: JSONValue] = [:]
        result.reserveCapacity(dictionary.count)

        for (key, entry) in dictionary {
            result[key] = try jsonValue(from: entry)
        }

        return .object(result)
    }

    if let array = value as? [Any] {
        let mapped = try array.map { try jsonValue(from: $0) }
        return .array(mapped)
    }

    if let string = value as? String {
        return .string(string)
    }

    // Individual number checks (Double, Int, Float) are now unreachable
    // because NSNumber check above catches all numeric types from JSONSerialization.
    // Keeping them for defensive programming in case non-JSONSerialization values are passed.

    if let double = value as? Double {
        return .number(double)
    }

    if let int = value as? Int {
        return .number(Double(int))
    }

    if let float = value as? Float {
        return .number(Double(float))
    }

    throw JSONParseError(text: "\(value)", cause: SchemaJSONSerializationError(value: value))
}
