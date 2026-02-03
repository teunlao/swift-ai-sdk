import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/mistral/src/mistral-prepare-tools.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

struct MistralPreparedTools: Sendable {
    let tools: [JSONValue]?
    let toolChoice: JSONValue?
    let toolWarnings: [SharedV3Warning]
}

func prepareMistralTools(
    tools: [LanguageModelV3Tool]?,
    toolChoice: LanguageModelV3ToolChoice?
) -> MistralPreparedTools {
    guard let tools, !tools.isEmpty else {
        return MistralPreparedTools(tools: nil, toolChoice: nil, toolWarnings: [])
    }

    var warnings: [SharedV3Warning] = []
    var functionTools: [(name: String, payload: JSONValue)] = []

    for tool in tools {
        switch tool {
        case .function(let functionTool):
            var functionPayload: [String: JSONValue] = [
                "name": .string(functionTool.name),
                "parameters": functionTool.inputSchema
            ]
            if let description = functionTool.description {
                functionPayload["description"] = .string(description)
            }
            if let strict = functionTool.strict {
                functionPayload["strict"] = .bool(strict)
            }
            functionTools.append((functionTool.name, .object([
                "type": .string("function"),
                "function": .object(functionPayload)
            ])))

        case .provider(let providerTool):
            warnings.append(.unsupported(feature: "provider-defined tool \(providerTool.id)", details: nil))
        }
    }

    var toolPayloads = functionTools.map { $0.payload }
    var toolChoiceJSON: JSONValue?

    if let toolChoice {
        switch toolChoice {
        case .auto:
            toolChoiceJSON = .string("auto")
        case .none:
            toolChoiceJSON = .string("none")
        case .required:
            toolChoiceJSON = .string("any")
        case .tool(let toolName):
            toolPayloads = functionTools
                .filter { $0.name == toolName }
                .map { $0.payload }
            toolChoiceJSON = .string("any")
        }
    }

    return MistralPreparedTools(
        tools: toolPayloads.isEmpty ? nil : toolPayloads,
        toolChoice: toolChoiceJSON,
        toolWarnings: warnings
    )
}
