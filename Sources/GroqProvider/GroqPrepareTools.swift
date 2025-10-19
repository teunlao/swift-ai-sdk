import Foundation
import AISDKProvider
import AISDKProviderUtils

struct GroqPreparedTools: Sendable {
    let tools: [JSONValue]?
    let toolChoice: JSONValue?
    let toolWarnings: [LanguageModelV3CallWarning]
}

func prepareGroqTools(
    tools: [LanguageModelV3Tool]?,
    toolChoice: LanguageModelV3ToolChoice?,
    modelId: GroqChatModelId
) -> GroqPreparedTools {
    guard let tools, !tools.isEmpty else {
        return GroqPreparedTools(tools: nil, toolChoice: nil, toolWarnings: [])
    }

    var toolWarnings: [LanguageModelV3CallWarning] = []
    var groqTools: [JSONValue] = []

    for tool in tools {
        switch tool {
        case .function(let functionTool):
            groqTools.append(.object([
                "type": .string("function"),
                "function": .object({ () -> [String: JSONValue] in
                    var inner: [String: JSONValue] = ["name": .string(functionTool.name)]
                    if let description = functionTool.description {
                        inner["description"] = .string(description)
                    }
                    inner["parameters"] = functionTool.inputSchema
                    return inner
                }())
            ]))

        case .providerDefined(let providerTool):
            if providerTool.id == "groq.browser_search" {
                if GroqBrowserSearchSupportedModels.isSupported(modelId: modelId.rawValue) {
                    groqTools.append(.object([
                        "type": .string("browser_search")
                    ]))
                } else {
                    toolWarnings.append(
                        .unsupportedTool(
                            tool: tool,
                            details: "Browser search is only supported on the following models: \(GroqBrowserSearchSupportedModels.supportedModelsString()). Current model: \(modelId.rawValue)"
                        )
                    )
                }
            } else {
                toolWarnings.append(.unsupportedTool(tool: tool, details: nil))
            }
        }
    }

    let toolChoiceJSON: JSONValue?
    if let toolChoice {
        switch toolChoice {
        case .auto:
            toolChoiceJSON = .string("auto")
        case .none:
            toolChoiceJSON = .string("none")
        case .required:
            toolChoiceJSON = .string("required")
        case .tool(let name):
            toolChoiceJSON = .object([
                "type": .string("function"),
                "function": .object([
                    "name": .string(name)
                ])
            ])
        }
    } else {
        toolChoiceJSON = nil
    }

    return GroqPreparedTools(
        tools: groqTools.isEmpty ? nil : groqTools,
        toolChoice: toolChoiceJSON,
        toolWarnings: toolWarnings
    )
}

private enum GroqBrowserSearchSupportedModels {
    private static let supported: Set<String> = [
        "openai/gpt-oss-20b",
        "openai/gpt-oss-120b"
    ]

    static func isSupported(modelId: String) -> Bool {
        supported.contains(modelId)
    }

    static func supportedModelsString() -> String {
        supported.sorted().joined(separator: ", ")
    }
}
