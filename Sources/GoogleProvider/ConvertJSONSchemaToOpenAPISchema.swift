import Foundation
import AISDKProvider

func convertJSONSchemaToOpenAPISchema(_ jsonSchema: JSONValue?) -> Any? {
    guard let jsonSchema else { return nil }

    if isEmptyGoogleObjectSchema(jsonSchema) {
        return nil
    }

    switch jsonSchema {
    case .bool:
        return [
            "type": "boolean",
            "properties": [:] as [String: Any]
        ]
    case .object(let dict):
        var result: [String: Any] = [:]

        if let description = dict.stringValue(forKey: "description") {
            result["description"] = description
        }

        if let requiredArray = dict.arrayOfStrings(forKey: "required") {
            result["required"] = requiredArray
        }

        if let format = dict.stringValue(forKey: "format") {
            result["format"] = format
        }

        if let constValue = dict["const"], constValue != .null {
            result["enum"] = [constValue.toAny()]
        }

        if let typeValue = dict["type"], typeValue != .null {
            switch typeValue {
            case .array(let array):
                var types: [String] = []
                for element in array {
                    if case .string(let str) = element {
                        types.append(str)
                    }
                }
                if let nullIndex = types.firstIndex(of: "null") {
                    types.remove(at: nullIndex)
                    result["nullable"] = true
                }
                if let first = types.first {
                    result["type"] = types.count == 1 ? first : types
                }
            case .string(let string):
                result["type"] = string
            default:
                break
            }
        }

        if let enumArray = dict["enum"], enumArray != .null {
            switch enumArray {
            case .array(let array):
                result["enum"] = array.map { $0.toAny() }
            default:
                break
            }
        }

        if let propertiesValue = dict["properties"], case .object(let propertiesDict) = propertiesValue {
            var properties: [String: Any] = [:]
            for (key, value) in propertiesDict {
                properties[key] = convertJSONSchemaToOpenAPISchema(value)
            }
            result["properties"] = properties
        }

        if let itemsValue = dict["items"], itemsValue != .null {
            switch itemsValue {
            case .array(let array):
                result["items"] = array.map { convertJSONSchemaToOpenAPISchema($0) as Any }
            default:
                result["items"] = convertJSONSchemaToOpenAPISchema(itemsValue)
            }
        }

        if let allOfValue = dict["allOf"], case .array(let array) = allOfValue {
            result["allOf"] = array.compactMap { convertJSONSchemaToOpenAPISchema($0) }
        }

        if let anyOfValue = dict["anyOf"], case .array(let array) = anyOfValue {
            let containsNull = array.contains { element in
                if case .object(let obj) = element, obj.stringValue(forKey: "type") == "null" {
                    return true
                }
                if case .string("null") = element {
                    return true
                }
                return false
            }

            if containsNull {
                let nonNullSchemas = array.filter { element in
                    if case .object(let obj) = element, obj.stringValue(forKey: "type") == "null" {
                        return false
                    }
                    if case .string("null") = element {
                        return false
                    }
                    return true
                }

                if nonNullSchemas.count == 1, let converted = convertJSONSchemaToOpenAPISchema(nonNullSchemas.first) as? [String: Any] {
                    result.merge(converted) { _, new in new }
                    result["nullable"] = true
                } else {
                    result["anyOf"] = nonNullSchemas.compactMap { convertJSONSchemaToOpenAPISchema($0) }
                    result["nullable"] = true
                }
            } else {
                result["anyOf"] = array.compactMap { convertJSONSchemaToOpenAPISchema($0) }
            }
        }

        if let oneOfValue = dict["oneOf"], case .array(let array) = oneOfValue {
            result["oneOf"] = array.compactMap { convertJSONSchemaToOpenAPISchema($0) }
        }

        if let minLength = dict.numberValue(forKey: "minLength") {
            result["minLength"] = minLength
        }

        return result
    default:
        return jsonSchema.toAny()
    }
}

private func isEmptyGoogleObjectSchema(_ value: JSONValue) -> Bool {
    guard case .object(let dict) = value else { return false }

    if dict.stringValue(forKey: "type") != "object" {
        return false
    }

    let propertiesEmpty: Bool
    if let propertiesValue = dict["properties"], case .object(let propertiesDict) = propertiesValue {
        propertiesEmpty = propertiesDict.isEmpty
    } else if dict["properties"] == nil {
        propertiesEmpty = true
    } else {
        propertiesEmpty = false
    }

    let additionalPropertiesDisabled: Bool
    if let additionalValue = dict["additionalProperties"] {
        switch additionalValue {
        case .bool(let bool): additionalPropertiesDisabled = !bool
        case .null: additionalPropertiesDisabled = true
        default: additionalPropertiesDisabled = false
        }
    } else {
        additionalPropertiesDisabled = false
    }

    return propertiesEmpty && additionalPropertiesDisabled
}

private extension JSONValue {
    func toAny() -> Any {
        switch self {
        case .null: return NSNull()
        case .bool(let value): return value
        case .number(let value): return value
        case .string(let value): return value
        case .array(let array): return array.map { $0.toAny() }
        case .object(let dict):
            var result: [String: Any] = [:]
            for (key, value) in dict {
                result[key] = value.toAny()
            }
            return result
        }
    }
}

private extension Dictionary where Key == String, Value == JSONValue {
    func stringValue(forKey key: String) -> String? {
        guard let value = self[key], case .string(let string) = value else { return nil }
        return string
    }

    func arrayOfStrings(forKey key: String) -> [String]? {
        guard let value = self[key] else { return nil }
        switch value {
        case .array(let array):
            return array.compactMap { element in
                if case .string(let string) = element { return string }
                return nil
            }
        default:
            return nil
        }
    }

    func numberValue(forKey key: String) -> Double? {
        guard let value = self[key] else { return nil }
        if case .number(let number) = value { return number }
        return nil
    }
}
