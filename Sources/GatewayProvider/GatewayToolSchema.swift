import AISDKProvider
import AISDKProviderUtils

func gatewayToolSchema(_ schema: JSONValue) -> FlexibleSchema<JSONValue> {
    FlexibleSchema(Schema(jsonSchemaResolver: { schema }, validator: { value in
        let json = try jsonValue(from: value)
        let parsed = await parseGatewayToolValue(json, schema: schema)
        return await jsonSchema(schema).validate(parsed)
    }))
}

private func parseGatewayToolValue(_ value: JSONValue, schema: JSONValue) async -> JSONValue {
    guard case .object(let definition) = schema else { return value }
    if case .array(let branches)? = definition["anyOf"] {
        for branch in branches {
            let parsed = await parseGatewayToolValue(value, schema: branch)
            if await jsonSchema(branch).validate(parsed).error == nil {
                return parsed
            }
        }
        return value
    }
    if case .array(let values) = value, let itemSchema = definition["items"] {
        var parsed: [JSONValue] = []
        for item in values {
            parsed.append(await parseGatewayToolValue(item, schema: itemSchema))
        }
        return .array(parsed)
    }
    guard case .object(let fields) = value else { return value }
    let properties: [String: JSONValue]
    if case .object(let defined)? = definition["properties"] {
        properties = defined
    } else {
        properties = [:]
    }
    var parsed: [String: JSONValue] = [:]
    for (name, field) in fields {
        if let fieldSchema = properties[name] {
            parsed[name] = await parseGatewayToolValue(field, schema: fieldSchema)
        } else if definition["additionalProperties"] != .bool(false) {
            if let fieldSchema = definition["additionalProperties"] {
                parsed[name] = await parseGatewayToolValue(field, schema: fieldSchema)
            } else {
                parsed[name] = field
            }
        }
    }
    return .object(parsed)
}
