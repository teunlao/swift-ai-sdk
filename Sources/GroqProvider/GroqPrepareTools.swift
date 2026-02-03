import Foundation
import AISDKProvider
import AISDKProviderUtils

struct GroqPreparedTools: Sendable {
    let tools: [JSONValue]?
    let toolChoice: JSONValue?
    let toolWarnings: [SharedV3Warning]
}

func prepareGroqTools(
    tools: [LanguageModelV3Tool]?,
    toolChoice: LanguageModelV3ToolChoice?,
    modelId: GroqChatModelId
) -> GroqPreparedTools {
    guard let tools, !tools.isEmpty else {
        return GroqPreparedTools(tools: nil, toolChoice: nil, toolWarnings: [])
    }

    var toolWarnings: [SharedV3Warning] = []
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

        case .provider(let providerTool):
            if providerTool.id == "groq.browser_search" {
                if GroqBrowserSearchSupportedModels.isSupported(modelId: modelId.rawValue) {
                    groqTools.append(.object([
                        "type": .string("browser_search")
                    ]))
                } else {
                    toolWarnings.append(
                        .unsupported(
                            feature: "provider-defined tool \(providerTool.id)",
                            details: "Browser search is only supported on the following models: \(GroqBrowserSearchSupportedModels.supportedModelsString()). Current model: \(modelId.rawValue)"
                        )
                    )
                }
            } else {
                toolWarnings.append(.unsupported(feature: "provider-defined tool \(providerTool.id)", details: nil))
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
