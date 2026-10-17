import AISDKProvider

struct OpenResponsesPreparedTools {
    let tools: [JSONValue]
    let choice: JSONValue?
    let warnings: [SharedV4Warning]
}

func prepareOpenResponsesTools(_ tools: [LanguageModelV4Tool]?, choice: LanguageModelV4ToolChoice?, config: OpenResponsesConfig, providerTools: [String: LanguageModelV4ProviderTool]) async -> OpenResponsesPreparedTools {
    var converted: [JSONValue] = []
    var warnings: [SharedV4Warning] = []
    var encoded: [String: (OpenResponsesExtensionRegistry.Tool, LanguageModelV4ProviderTool)] = [:]
    for tool in tools ?? [] {
        switch tool {
        case .function(let value):
            var fields: JSONObject = ["type": "function", "name": .string(value.name), "parameters": value.inputSchema]
            if let description = value.description { fields["description"] = .string(description) }
            if let strict = value.strict { fields["strict"] = .bool(strict) }
            converted.append(.object(fields))
        case .provider(let value):
            if value.id == config.customToolId {
                var fields: JSONObject = ["type": "custom", "name": .string(value.name)]
                if let description = openResponsesString(value.args["description"]) { fields["description"] = .string(description) }
                if case .object(let format) = value.args["format"] {
                    if format["type"] == "text" { fields["format"] = ["type": "text"] }
                    else if format["type"] == "grammar", let syntax = openResponsesString(format["syntax"]), ["regex", "lark"].contains(syntax), let definition = openResponsesString(format["definition"]) {
                        fields["format"] = ["type": "grammar", "syntax": .string(syntax), "definition": .string(definition)]
                    }
                }
                converted.append(.object(fields))
            } else {
                var fields: JSONObject?
                if let capability = config.extensions.byProviderToolId[value.id] {
                    do { fields = try await capability.encode(value.name, value.args) }
                    catch { /* Encoding failure is reported as an unsupported tool. */ }
                    if var fields {
                        fields["type"] = .string(capability.type)
                        converted.append(.object(fields))
                        encoded[value.name] = (capability, value)
                    }
                }
                if fields == nil { warnings.append(.unsupported(feature: "provider-defined tool \(value.id)", details: nil)) }
            }
        }
    }
    var convertedChoice: JSONValue?
    if let choice {
        switch choice {
        case .auto: convertedChoice = "auto"
        case .none: convertedChoice = "none"
        case .required: convertedChoice = "required"
        case .tool(let name):
            if let (capability, tool) = encoded[name] {
                if let encode = capability.owner.encodeChoice {
                    var fields: JSONObject?
                    do { fields = try await encode(tool.name, tool.args) }
                    catch { /* Encoding failure is reported as an unsupported choice. */ }
                    if var fields {
                        fields["type"] = .string(capability.type)
                        convertedChoice = .object(fields)
                    } else { warnings.append(.unsupported(feature: "tool choice for provider-defined tool \(tool.id)", details: nil)) }
                } else { convertedChoice = ["type": .string(capability.type)] }
            } else if providerTools[name]?.id == config.customToolId { convertedChoice = ["type": "custom", "name": .string(name)] }
            else if providerTools[name] == nil { convertedChoice = ["type": "function", "name": .string(name)] }
        }
    }
    return .init(tools: converted, choice: convertedChoice, warnings: warnings)
}
