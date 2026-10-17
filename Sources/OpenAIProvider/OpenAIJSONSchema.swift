import Foundation
import AISDKProvider
import AISDKProviderUtils

func openAIToolSchema(_ schema: JSONValue, strict: Bool = false) -> FlexibleSchema<JSONValue> {
    FlexibleSchema(Schema(jsonSchemaResolver: { schema }, validator: { value in
        do {
            let json = try jsonValue(from: value)
            if strict, case .object(let fields) = json, case .object(let shape) = schema,
               case .object(let properties)? = shape["properties"], fields.keys.contains(where: { properties[$0] == nil }) {
                throw SchemaValidationIssuesError(vendor: "openai", issues: "Unrecognized tool argument")
            }
            let projected = try projectToolValue(json, schema: schema, root: schema)
            return await jsonSchema(schema).validate(projected)
        } catch {
            return .failure(error: TypeValidationError.wrap(value: value, cause: error))
        }
    }))
}

func openAIToolSchema<T: Decodable & Sendable>(_ type: T.Type, _ schema: JSONValue) -> FlexibleSchema<T> {
    FlexibleSchema(Schema(jsonSchemaResolver: { schema }, validator: { value in
        do {
            let projected = try await validateTypes(ValidateTypesOptions(value: value, schema: openAIToolSchema(schema)))
            return await Schema.codable(type, jsonSchema: schema).validate(jsonValueToFoundation(projected))
        } catch {
            return .failure(error: TypeValidationError.wrap(value: value, cause: error))
        }
    }))
}

private func projectToolValue(_ value: JSONValue, schema: JSONValue, root: JSONValue) throws -> JSONValue {
    guard case .object(let shape) = schema else { return value }
    if shape["type"] == .string("integer"), case .number(let number) = value, Int(exactly: number) == nil {
        throw SchemaValidationIssuesError(vendor: "openai", issues: "Expected a representable integer tool argument")
    }
    if case .string(let reference)? = shape["$ref"], reference.hasPrefix("#/") {
        var target = root
        for component in reference.dropFirst(2).components(separatedBy: "/") {
            let key = component.replacingOccurrences(of: "~1", with: "/", options: .literal).replacingOccurrences(of: "~0", with: "~", options: .literal)
            guard case .object(let object) = target, let next = object[key] else { return value }
            target = next
        }
        return try projectToolValue(value, schema: target, root: root)
    }
    if case .array(let branches)? = shape["anyOf"] ?? shape["oneOf"] {
        for branch in branches where toolBranchMatches(value, schema: branch) {
            return try projectToolValue(value, schema: branch, root: root)
        }
        return value
    }
    switch value {
    case .object(let values):
        guard case .object(let properties)? = shape["properties"] else {
            return shape["additionalProperties"] == .bool(false) ? .object([:]) : value
        }
        var result = shape["additionalProperties"] == .bool(false) ? [:] : values
        for (key, field) in properties {
            if let value = values[key] { result[key] = try projectToolValue(value, schema: field, root: root) }
        }
        return .object(result)
    case .array(let values):
        guard let items = shape["items"] else { return value }
        var result: [JSONValue] = []
        result.reserveCapacity(values.count)
        for value in values { result.append(try projectToolValue(value, schema: items, root: root)) }
        return .array(result)
    default: return value
    }
}

private func toolBranchMatches(_ value: JSONValue, schema: JSONValue) -> Bool {
    guard case .object(let shape) = schema else { return true }
    if case .array(let allowed)? = shape["enum"], !allowed.contains(value) { return false }
    if case .string(let type)? = shape["type"] {
        switch (type, value) {
        case ("string", .string), ("number", .number), ("integer", .number), ("boolean", .bool),
             ("object", .object), ("array", .array), ("null", .null): break
        default: return false
        }
    }
    if case .object(let fields) = value, case .object(let properties)? = shape["properties"], let discriminator = properties["type"] {
        if let type = fields["type"] { return toolBranchMatches(type, schema: discriminator) }
        if case .array(let required)? = shape["required"], required.contains(.string("type")) { return false }
    }
    return true
}

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
