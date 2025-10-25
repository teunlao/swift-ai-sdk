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
    let toolWarnings: [LanguageModelV3CallWarning]
}

func prepareMistralTools(
    tools: [LanguageModelV3Tool]?,
    toolChoice: LanguageModelV3ToolChoice?
) -> MistralPreparedTools {
    guard let tools, !tools.isEmpty else {
        return MistralPreparedTools(tools: nil, toolChoice: nil, toolWarnings: [])
    }

    var warnings: [LanguageModelV3CallWarning] = []
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
            functionTools.append((functionTool.name, .object([
                "type": .string("function"),
                "function": .object(functionPayload)
            ])))

        case .providerDefined:
            warnings.append(.unsupportedTool(tool: tool, details: nil))
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
