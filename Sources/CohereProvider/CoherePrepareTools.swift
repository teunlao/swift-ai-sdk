import Foundation
import AISDKProvider

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/cohere/src/cohere-prepare-tools.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

private struct CohereFunctionToolDefinition {
    let name: String
    let json: JSONValue
}

struct CoherePreparedTools {
    let tools: [JSONValue]?
    let toolChoice: CohereToolChoice?
    let toolWarnings: [LanguageModelV3CallWarning]
}

func prepareCohereTools(
    tools: [LanguageModelV3Tool]?,
    toolChoice: LanguageModelV3ToolChoice?
) -> CoherePreparedTools {
    let normalizedTools = (tools?.isEmpty == false) ? tools : nil
    var toolWarnings: [LanguageModelV3CallWarning] = []

    guard let normalizedTools else {
        return CoherePreparedTools(tools: nil, toolChoice: nil, toolWarnings: [])
    }

    var functionTools: [CohereFunctionToolDefinition] = []
    functionTools.reserveCapacity(normalizedTools.count)

    for tool in normalizedTools {
        switch tool {
        case .providerDefined:
            toolWarnings.append(.unsupportedTool(tool: tool, details: nil))

        case .function(let functionTool):
            var functionObject: [String: JSONValue] = [
                "name": .string(functionTool.name),
                "parameters": functionTool.inputSchema
            ]

            if let description = functionTool.description {
                functionObject["description"] = .string(description)
            }

            let toolJSON = JSONValue.object([
                "type": .string("function"),
                "function": .object(functionObject)
            ])

            functionTools.append(.init(name: functionTool.name, json: toolJSON))
        }
    }

    let serializedTools = functionTools.isEmpty ? nil : functionTools.map { $0.json }

    guard let toolChoice else {
        return CoherePreparedTools(tools: serializedTools, toolChoice: nil, toolWarnings: toolWarnings)
    }

    switch toolChoice {
    case .auto:
        return CoherePreparedTools(tools: serializedTools, toolChoice: nil, toolWarnings: toolWarnings)

    case .none:
        return CoherePreparedTools(tools: serializedTools, toolChoice: CohereToolChoice.none, toolWarnings: toolWarnings)

    case .required:
        return CoherePreparedTools(tools: serializedTools, toolChoice: CohereToolChoice.required, toolWarnings: toolWarnings)

    case .tool(let toolName):
        let filtered = functionTools.filter { $0.name == toolName }.map { $0.json }
        return CoherePreparedTools(tools: filtered.isEmpty ? nil : filtered, toolChoice: CohereToolChoice.required, toolWarnings: toolWarnings)

    @unknown default:
        return CoherePreparedTools(tools: serializedTools, toolChoice: nil, toolWarnings: toolWarnings)
    }
}
