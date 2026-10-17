import AISDKProvider

struct PerplexityPreparedTools {
    let tools: [JSONValue]
    let warnings: [SharedV4Warning]
}

func preparePerplexityTools(tools: [LanguageModelV4Tool]?, toolChoice: LanguageModelV4ToolChoice?) -> PerplexityPreparedTools {
    var output: [JSONValue] = []
    var warnings: [SharedV4Warning] = []
    for tool in tools ?? [] {
        switch tool {
        case .provider(let tool): warnings.append(.unsupported(feature: "provider-defined tool \(tool.name)", details: nil))
        case .function(let tool):
            var value: JSONObject = ["type": "function", "name": .string(tool.name), "parameters": tool.inputSchema]
            if let description = tool.description { value["description"] = .string(description) }
            if let strict = tool.strict { value["strict"] = .bool(strict) }
            output.append(.object(value))
        }
    }
    if let toolChoice, toolChoice != .auto {
        warnings.append(.unsupported(feature: "toolChoice", details: "The Perplexity Agent API currently selects tools automatically."))
    }
    return .init(tools: output, warnings: warnings)
}
