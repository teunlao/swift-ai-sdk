import AISDKProvider

struct CoherePreparedTools {
    let tools: [JSONValue]?
    let toolChoice: CohereToolChoice?
    let toolWarnings: [SharedV4Warning]
}

func prepareCohereTools(tools: [LanguageModelV4Tool]?, toolChoice: LanguageModelV4ToolChoice?) -> CoherePreparedTools {
    guard let tools, !tools.isEmpty else { return .init(tools: nil, toolChoice: nil, toolWarnings: []) }
    var functions: [(name: String, value: JSONValue)] = []
    var warnings: [SharedV4Warning] = []
    for tool in tools {
        switch tool {
        case .provider(let tool): warnings.append(.unsupported(feature: "provider-defined tool \(tool.id)", details: nil))
        case .function(let tool):
            var function: JSONObject = ["name": .string(tool.name), "parameters": tool.inputSchema]
            if let description = tool.description { function["description"] = .string(description) }
            functions.append((tool.name, ["type": "function", "function": .object(function)]))
        }
    }
    var choice: CohereToolChoice?
    if let toolChoice {
        switch toolChoice {
        case .auto: break
        case .none: choice = CohereToolChoice.none
        case .required: choice = .required
        case .tool(let name):
            functions = functions.filter { $0.name == name }
            choice = .required
        }
    }
    return .init(tools: functions.map(\.value), toolChoice: choice, toolWarnings: warnings)
}
