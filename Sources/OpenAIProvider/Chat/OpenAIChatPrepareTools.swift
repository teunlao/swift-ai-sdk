import AISDKProvider

struct OpenAIChatPreparedTools {
    let tools: JSONValue?
    let toolChoice: JSONValue?
    let warnings: [SharedV4Warning]
}

enum OpenAIChatToolPreparer {
    static func prepare(
        tools: [LanguageModelV4Tool]?,
        toolChoice: LanguageModelV4ToolChoice?
    ) throws -> OpenAIChatPreparedTools {
        guard let tools, !tools.isEmpty else {
            return OpenAIChatPreparedTools(tools: nil, toolChoice: nil, warnings: [])
        }
        var warnings: [SharedV4Warning] = []
        var prepared: [JSONValue] = []
        for tool in tools {
            switch tool {
            case .function(let function):
                let normalized = try normalizeOpenAIJsonSchema(function.inputSchema)
                warnings.append(contentsOf: normalized.warnings)
                var parameters: [String: JSONValue] = [
                    "name": .string(function.name), "parameters": normalized.schema
                ]
                if let description = function.description { parameters["description"] = .string(description) }
                if let strict = function.strict { parameters["strict"] = .bool(strict) }
                prepared.append(.object(["type": .string("function"), "function": .object(parameters)]))
            case .provider:
                warnings.append(.unsupported(feature: "tool type: provider", details: nil))
            }
        }
        let choice: JSONValue?
        switch toolChoice {
        case .auto: choice = .string("auto")
        case .some(.none): choice = .string("none")
        case .required: choice = .string("required")
        case .tool(let name):
            choice = .object(["type": .string("function"), "function": .object(["name": .string(name)])])
        case .none: choice = nil
        }
        return OpenAIChatPreparedTools(tools: .array(prepared), toolChoice: choice, warnings: warnings)
    }
}
