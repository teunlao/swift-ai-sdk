import AISDKProvider

func addAdditionalPropertiesToJsonSchema(_ jsonSchema: JSONValue) -> JSONValue {
    guard case .object(var schemaObject) = jsonSchema else {
        return jsonSchema
    }

    if schemaTypeIncludesObject(schemaObject["type"]) {
        schemaObject["additionalProperties"] = .bool(false)

        if case .object(let properties) = schemaObject["properties"] {
            schemaObject["properties"] = .object(properties.mapValues(visitJsonSchemaDefinition))
        }
    }

    if let items = schemaObject["items"] {
        switch items {
        case .array(let itemSchemas):
            schemaObject["items"] = .array(itemSchemas.map(visitJsonSchemaDefinition))
        default:
            schemaObject["items"] = visitJsonSchemaDefinition(items)
        }
    }

    for key in ["anyOf", "allOf", "oneOf"] {
        guard case .array(let schemas) = schemaObject[key] else {
            continue
        }
        schemaObject[key] = .array(schemas.map(visitJsonSchemaDefinition))
    }

    if case .object(let definitions) = schemaObject["definitions"] {
        schemaObject["definitions"] = .object(definitions.mapValues(visitJsonSchemaDefinition))
    }

    return .object(schemaObject)
}

private func visitJsonSchemaDefinition(_ definition: JSONValue) -> JSONValue {
    if case .bool = definition {
        return definition
    }

    return addAdditionalPropertiesToJsonSchema(definition)
}

private func schemaTypeIncludesObject(_ type: JSONValue?) -> Bool {
    switch type {
    case .string("object"):
        return true
    case .array(let values):
        return values.contains(.string("object"))
    default:
        return false
    }
}
