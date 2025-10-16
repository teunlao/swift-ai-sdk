import CoreFoundation
import CoreGraphics
import Foundation

/**
 Type guard helpers for JSON values.

 Port of `@ai-sdk/provider/src/json-value/is-json.ts`.
 */
public func isJSONValue(_ value: Any?) -> Bool {
    guard let value else {
        // Treat `nil` as JSON null.
        return true
    }

    if value is NSNull {
        return true
    }

    if let jsonValue = value as? JSONValue {
        return isJSONValue(jsonValue)
    }

    if value is String || value is NSString {
        return true
    }

    if value is Bool {
        return true
    }

    if isJSONNumber(value) {
        return true
    }

    if isJSONArray(value) {
        return true
    }

    if isJSONObject(value) {
        return true
    }

    return false
}

public func isJSONArray(_ value: Any?) -> Bool {
    guard let value else {
        return false
    }

    if let jsonValue = value as? JSONValue {
        if case let .array(elements) = jsonValue {
            return elements.allSatisfy(isJSONValue)
        }
        return false
    }

    if let array = value as? JSONArray {
        return array.allSatisfy(isJSONValue)
    }

    if let array = value as? [Any] {
        return array.allSatisfy { element in
            isJSONValue(element)
        }
    }

    if let array = value as? NSArray {
        for element in array {
            if !isJSONValue(element) {
                return false
            }
        }
        return true
    }

    return false
}

public func isJSONObject(_ value: Any?) -> Bool {
    guard let value else {
        return false
    }

    if let jsonValue = value as? JSONValue {
        if case let .object(object) = jsonValue {
            return object.values.allSatisfy(isJSONValue)
        }
        return false
    }

    if let dictionary = value as? JSONObject {
        return dictionary.values.allSatisfy(isJSONValue)
    }

    if let dictionary = value as? [String: Any] {
        return dictionary.values.allSatisfy { element in
            isJSONValue(element)
        }
    }

    if let dictionary = value as? NSDictionary {
        for rawKey in dictionary.allKeys {
            guard let key = rawKey as? String else {
                return false
            }
            guard let element = dictionary.object(forKey: key) else {
                return false
            }
            if !isJSONValue(element) {
                return false
            }
        }

        return true
    }

    return false
}

private func isJSONValue(_ value: JSONValue) -> Bool {
    switch value {
    case .null, .bool, .number, .string:
        return true
    case .array(let array):
        return array.allSatisfy(isJSONValue)
    case .object(let dictionary):
        return dictionary.values.allSatisfy(isJSONValue)
    }
}

private func isJSONNumber(_ value: Any) -> Bool {
    switch value {
    case is Int, is Int8, is Int16, is Int32, is Int64,
         is UInt, is UInt8, is UInt16, is UInt32, is UInt64,
         is Float, is Double, is CGFloat, is Decimal:
        return true
    case let number as NSNumber:
        return CFGetTypeID(number) != CFBooleanGetTypeID()
    default:
        return false
    }
}
