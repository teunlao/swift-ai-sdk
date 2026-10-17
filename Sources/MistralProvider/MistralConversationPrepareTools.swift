import AISDKProvider
import AISDKProviderUtils

let mistralProviderToolNames = [
    "mistral.web_search": "web_search",
    "mistral.web_search_premium": "web_search_premium"
]

func prepareMistralConversationTools(
    tools: [LanguageModelV4Tool]?,
    toolChoice: LanguageModelV4ToolChoice?
) -> MistralPreparedTools {
    guard let tools, !tools.isEmpty else {
        return .init(tools: nil, toolChoice: nil, toolWarnings: [])
    }
    var payloads: [(name: String, value: JSONValue)] = []
    var warnings: [SharedV4Warning] = []
    for tool in tools {
        switch tool {
        case .provider(let tool):
            if let name = mistralProviderToolNames[tool.id] {
                payloads.append((name, .object(["type": .string(name)])))
            } else {
                warnings.append(.unsupported(feature: "provider-defined tool \(tool.id)", details: nil))
            }
        case .function(let tool):
            var function: JSONObject = ["name": .string(tool.name), "parameters": tool.inputSchema]
            if let description = tool.description { function["description"] = .string(description) }
            if let strict = tool.strict { function["strict"] = .bool(strict) }
            payloads.append((tool.name, .object(["type": .string("function"), "function": .object(function)])))
        }
    }
    var choice: JSONValue?
    if let toolChoice {
        switch toolChoice {
        case .auto: choice = .string("auto")
        case .none: choice = .string("none")
        case .required: choice = .string("any")
        case .tool(let name):
            let mapping = createToolNameMapping(tools: tools, providerToolNames: mistralProviderToolNames)
            let providerName = mapping.toProviderToolName(name)
            payloads = payloads.filter { $0.name == providerName }
            choice = .string("any")
        }
    }
    return .init(tools: payloads.map(\.value), toolChoice: choice, toolWarnings: warnings)
}
