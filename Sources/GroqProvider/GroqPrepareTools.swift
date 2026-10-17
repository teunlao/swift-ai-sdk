import Foundation
import AISDKProvider
import AISDKProviderUtils

struct GroqPreparedTools: Sendable {
    let tools: [JSONValue]?
    let toolChoice: JSONValue?
    let toolWarnings: [SharedV4Warning]
}

func prepareGroqTools(
    tools: [LanguageModelV4Tool]?,
    toolChoice: LanguageModelV4ToolChoice?,
    modelId: GroqChatModelId
) -> GroqPreparedTools {
    guard let tools, !tools.isEmpty else {
        return GroqPreparedTools(tools: nil, toolChoice: nil, toolWarnings: [])
    }

    var toolWarnings: [SharedV4Warning] = []
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
                    if let strict = functionTool.strict { inner["strict"] = .bool(strict) }
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
                            details: "Browser search is not supported on model \(modelId.rawValue)."
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
        tools: groqTools,
        toolChoice: toolChoiceJSON,
        toolWarnings: toolWarnings
    )
}

private enum GroqBrowserSearchSupportedModels {
    private static let unsupported: Set<String> = [
        "gemma2-9b-it", "llama-3.1-8b-instant", "llama-3.3-70b-versatile", "meta-llama/llama-guard-4-12b",
        "deepseek-r1-distill-llama-70b", "meta-llama/llama-4-maverick-17b-128e-instruct", "meta-llama/llama-4-scout-17b-16e-instruct",
        "meta-llama/llama-prompt-guard-2-22m", "meta-llama/llama-prompt-guard-2-86m", "moonshotai/kimi-k2-instruct-0905",
        "qwen/qwen3.6-27b", "llama-guard-3-8b", "llama3-70b-8192", "llama3-8b-8192", "mixtral-8x7b-32768",
        "qwen-qwq-32b", "qwen-2.5-32b", "deepseek-r1-distill-qwen-32b"
    ]

    static func isSupported(modelId: String) -> Bool { !unsupported.contains(modelId) }
}
