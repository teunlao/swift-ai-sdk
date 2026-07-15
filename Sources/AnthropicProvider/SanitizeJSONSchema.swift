import Foundation
import AISDKProvider
import AISDKProviderUtils

private let anthropicSupportedStringFormats: Set<String> = [
    "date-time",
    "time",
    "date",
    "duration",
    "email",
    "hostname",
    "uri",
    "ipv4",
    "ipv6",
    "uuid",
]

private let anthropicDescriptionConstraintKeys = [
    "minimum",
    "maximum",
    "exclusiveMinimum",
    "exclusiveMaximum",
    "multipleOf",
    "minLength",
    "maxLength",
    "pattern",
    "minItems",
    "maxItems",
    "uniqueItems",
    "minProperties",
    "maxProperties",
    "not",
]

func sanitizeAnthropicJSONSchema(_ schema: JSONValue) -> JSONValue {
    guard case .object(let object) = schema else {
        return schema
    }

    if let reference = object["$ref"], reference != .null {
        return .object(["$ref": reference])
    }

    var result: [String: JSONValue] = [:]

    for key in ["$schema", "$id", "title", "description", "enum", "type"] {
        if let value = object[key], value != .null {
            result[key] = value
        }
    }
    for key in ["default", "const"] {
        if let value = object[key] {
            result[key] = value
        }
    }

    if case .array(let definitions) = object["anyOf"] {
        result["anyOf"] = .array(definitions.map(sanitizeAnthropicDefinition))
    } else if case .array(let definitions) = object["oneOf"] {
        result["anyOf"] = .array(definitions.map(sanitizeAnthropicDefinition))
    }

    if case .array(let definitions) = object["allOf"] {
        result["allOf"] = .array(definitions.map(sanitizeAnthropicDefinition))
    }

    for key in ["definitions", "$defs"] {
        if case .object(let definitions) = object[key] {
            result[key] = .object(definitions.mapValues(sanitizeAnthropicDefinition))
        }
    }

    if object["type"] == .string("object") || object["properties"] != nil {
        if case .object(let properties) = object["properties"] {
            result["properties"] = .object(properties.mapValues(sanitizeAnthropicDefinition))
        }
        result["additionalProperties"] = .bool(false)
        if let required = object["required"], required != .null {
            result["required"] = required
        }
    }

    if let items = object["items"], items != .null {
        if case .array(let definitions) = items {
            result["items"] = .array(definitions.map(sanitizeAnthropicDefinition))
        } else {
            result["items"] = sanitizeAnthropicDefinition(items)
        }
    }

    if case .string(let format) = object["format"], anthropicSupportedStringFormats.contains(format) {
        result["format"] = .string(format)
    }

    if let constraints = anthropicConstraintDescription(object) {
        if case .string(let description) = result["description"] {
            result["description"] = .string("\(description)\n\(constraints)")
        } else {
            result["description"] = .string(constraints)
        }
    }

    return .object(result)
}

private func sanitizeAnthropicDefinition(_ definition: JSONValue) -> JSONValue {
    guard case .object = definition else {
        return definition
    }
    return sanitizeAnthropicJSONSchema(definition)
}

private func anthropicConstraintDescription(_ schema: [String: JSONValue]) -> String? {
    var descriptions: [String] = []

    for key in anthropicDescriptionConstraintKeys {
        guard let value = schema[key], value != .null, value != .bool(false) else {
            continue
        }
        descriptions.append("\(anthropicConstraintName(key)): \(anthropicConstraintValue(value))")
    }

    if case .string(let format) = schema["format"], !anthropicSupportedStringFormats.contains(format) {
        descriptions.append("format: \(format)")
    }

    return descriptions.isEmpty ? nil : "\(descriptions.joined(separator: "; "))."
}

private func anthropicConstraintName(_ key: String) -> String {
    var result = ""
    for scalar in key.unicodeScalars {
        if scalar.value >= 65, scalar.value <= 90 {
            result.append(" ")
            result.append(Character(String(scalar).lowercased()))
        } else {
            result.append(Character(scalar))
        }
    }
    return result
}

private func anthropicConstraintValue(_ value: JSONValue) -> String {
    if case .string(let string) = value {
        return string
    }

    let foundationValue = jsonValueToFoundation(value)
    guard let data = try? JSONSerialization.data(
        withJSONObject: foundationValue,
        options: [.fragmentsAllowed, .sortedKeys]
    ) else {
        return String(describing: foundationValue)
    }
    return String(decoding: data, as: UTF8.self)
}
