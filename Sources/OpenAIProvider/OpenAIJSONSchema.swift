import Foundation
import AISDKProvider

func normalizeOpenAIJsonSchema(_ schema: JSONValue) throws -> (schema: JSONValue, warnings: [SharedV4Warning]) {
    var removedNames = false
    var removedPattern = false

    func hasLookaround(_ pattern: String) -> Bool {
        // ASCII syntax must stay separate from adjacent combining marks, as in JavaScript.
        let bytes = Array(pattern.utf8)
        var escaped = false
        var inClass = false
        for index in bytes.indices {
            let byte = bytes[index]
            if escaped { escaped = false; continue }
            if byte == 0x5c { escaped = true; continue }
            if byte == 0x5b { inClass = true; continue }
            if byte == 0x5d { inClass = false; continue }
            if !inClass && byte == 0x28 && index + 2 < bytes.count && bytes[index + 1] == 0x3f {
                if bytes[index + 2] == 0x3d || bytes[index + 2] == 0x21 { return true }
                if bytes[index + 2] == 0x3c && index + 3 < bytes.count && (bytes[index + 3] == 0x3d || bytes[index + 3] == 0x21) { return true }
            }
        }
        return false
    }

    func normalize(_ value: JSONValue, root: Bool = false) throws -> JSONValue {
        guard case .object(var object) = value else { return value }
        if let names = object["propertyNames"], names != .null {
            guard case .object(let namesSchema) = names, namesSchema["type"] == .string("string") else {
                throw UnsupportedFunctionalityError(functionality: "JSON Schema propertyNames that does not use a string schema")
            }
            removedNames = true
        }
        object.removeValue(forKey: "propertyNames")
        if case .string(let pattern)? = object["pattern"], hasLookaround(pattern) {
            object.removeValue(forKey: "pattern")
            removedPattern = true
        }
        for key in ["properties", "patternProperties", "definitions", "$defs"] {
            if case .object(let record)? = object[key] {
                object[key] = .object(try record.mapValues { try normalize($0) })
            }
        }
        for key in ["additionalProperties", "additionalItems", "contains", "not", "if", "then", "else"] {
            if let nested = object[key], nested != .null { object[key] = try normalize(nested) }
        }
        if let items = object["items"], items != .null {
            if case .array(let values) = items { object["items"] = .array(try values.map { try normalize($0) }) }
            else { object["items"] = try normalize(items) }
        }
        for key in ["allOf", "anyOf", "oneOf"] {
            if case .array(let values)? = object[key] { object[key] = .array(try values.map { try normalize($0) }) }
        }
        if case .object(let dependencies)? = object["dependencies"] {
            object["dependencies"] = .object(try dependencies.mapValues { value in
                if case .array = value { return value }
                return try normalize(value)
            })
        }
        guard case .array(let allOf)? = object["allOf"], allOf.count == 1,
              case .object(let reference) = allOf[0], reference.count == 1,
              case .string(let ref)? = reference["$ref"] else { return .object(object) }
        if !root {
            object.removeValue(forKey: "allOf")
            object["$ref"] = .string(ref)
            return .object(object)
        }
        let prefixes = ["#/definitions/": "definitions", "#/$defs/": "$defs"]
        for (prefix, key) in prefixes where ref.utf8.starts(with: prefix.utf8) {
            let encodedName = String(decoding: ref.utf8.dropFirst(prefix.utf8.count), as: UTF8.self)
            guard !encodedName.isEmpty,
                  !encodedName.unicodeScalars.contains(where: { [0x0a, 0x0d, 0x2028, 0x2029].contains($0.value) }) else {
                continue
            }
            let name = encodedName.replacingOccurrences(of: "~1", with: "/", options: .literal).replacingOccurrences(of: "~0", with: "~", options: .literal)
            if case .object(let definitions)? = object[key], case .object(var definition)? = definitions[name] {
                object.removeValue(forKey: "allOf")
                definition.merge(object) { _, current in current }
                return .object(definition)
            }
        }
        return .object(object)
    }

    let normalized = try normalize(schema, root: true)
    var warnings: [SharedV4Warning] = []
    if removedNames {
        warnings.append(.compatibility(feature: "JSON Schema propertyNames", details: "OpenAI does not support JSON Schema propertyNames. It was removed before sending the schema, so OpenAI will not enforce property-name constraints."))
    }
    if removedPattern {
        warnings.append(.compatibility(feature: "JSON Schema pattern with regex lookaround", details: "OpenAI does not support regex lookaround in JSON Schema patterns. The pattern was removed before sending the schema, so OpenAI will not enforce that constraint."))
    }
    return (normalized, warnings)
}
