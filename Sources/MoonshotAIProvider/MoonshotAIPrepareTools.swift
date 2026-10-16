import AISDKProvider

func normalizeJsonSchemaForMFJS(_ schema: JSONValue) throws -> JSONValue { try normalizeDefinition(schema, root: true) }

private func normalizeDefinition(_ definition: JSONValue, root: Bool) throws -> JSONValue {
    guard case .object(var result) = definition else {
        if root { throw schemaRootError() }
        return definition
    }
    if root && result["type"] != .string("object") { throw schemaRootError() }
    if case .array(let items) = result["items"] {
        let prefix: [JSONValue]
        if case .array(let value) = result["prefixItems"] { prefix = value } else { prefix = [] }
        result["prefixItems"] = .array(prefix + (try items.map { try normalizeDefinition($0, root: false) }))
        result["items"] = nil
    } else if case .object = result["items"] { result["items"] = try normalizeDefinition(result["items"]!, root: false) }
    if case .string(let type) = result["type"], case .array(let branches) = result["anyOf"] {
        result["type"] = nil
        result["anyOf"] = .array(branches.map { branch in
            guard case .object(let object) = branch, object["type"] == nil || object["type"] == .null else { return branch }
            return .object(["type": JSONValue.string(type)].merging(object) { _, new in new })
        })
    }
    for key in ["allOf", "anyOf", "oneOf", "prefixItems"] {
        if case .array(let array) = result[key] { result[key] = .array(try array.map { try normalizeDefinition($0, root: false) }) }
    }
    for key in ["properties", "patternProperties", "$defs", "dependentSchemas"] {
        if case .object(let object) = result[key] { result[key] = .object(try object.mapValues { try normalizeDefinition($0, root: false) }) }
    }
    for key in ["additionalProperties", "propertyNames", "items", "contains", "not", "if", "then", "else"] {
        if let value = result[key] {
            switch value {
            case .object, .bool: result[key] = try normalizeDefinition(value, root: false)
            default: break
            }
        }
    }
    return .object(result)
}
private func schemaRootError() -> UnsupportedFunctionalityError { .init(functionality: "tool parameters must be a JSON Schema object with type \"object\" for moonshotai (MFJS)") }

func prepareMoonshotTools(tools: [LanguageModelV4Tool]?, choice: LanguageModelV4ToolChoice? = nil, modelId: String) throws -> (tools: [JSONValue]?, choice: JSONValue?, warnings: [SharedV4Warning]) {
    guard let tools, !tools.isEmpty else { return (nil, nil, []) }
    var warnings: [SharedV4Warning] = []
    var result: [JSONValue] = []
    for tool in tools {
        switch tool {
        case .provider(let tool): warnings.append(.unsupported(feature: "provider-defined tool \(tool.id)", details: nil))
        case .function(let tool):
            var function: [String: JSONValue] = ["name": .string(tool.name), "parameters": try normalizeJsonSchemaForMFJS(tool.inputSchema)]
            if let description = tool.description { function["description"] = .string(description) }
            if let strict = tool.strict { function["strict"] = .bool(strict) }
            result.append(.object(["type": .string("function"), "function": .object(function)]))
        }
    }
    let resolved: JSONValue?
    switch choice {
    case nil: resolved = nil
    case .auto: resolved = .string("auto")
    case .some(.none): resolved = .string("none")
    case .required:
        if ["kimi-k2.6", "kimi-k2.7-code", "kimi-k2.7-code-highspeed"].contains(modelId) {
            warnings.append(.unsupported(feature: "tool choice \"required\" for model \"\(modelId)\"", details: "Moonshot AI rejects required tool choice for this model. The setting has been omitted; use \"auto\" or select a specific tool instead."))
            resolved = nil
        } else { resolved = .string("required") }
    case .tool(let name): resolved = .object(["type": .string("function"), "function": .object(["name": .string(name)])])
    }
    return (result, resolved, warnings)
}
