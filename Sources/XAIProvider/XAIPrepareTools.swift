import Foundation
import AISDKProvider

/// Converts SDK tool definitions into the xAI wire format.
/// Mirrors `packages/xai/src/xai-prepare-tools.ts`.
struct XAIPreparedTools {
    let tools: [JSONValue]?
    let toolChoice: JSONValue?
    let warnings: [SharedV3Warning]
}

func prepareXAITools(
    tools: [LanguageModelV3Tool]?,
    toolChoice: LanguageModelV3ToolChoice?
) -> XAIPreparedTools {
    let normalizedTools = tools?.isEmpty == true ? nil : tools
    var warnings: [SharedV3Warning] = []

    guard let normalizedTools else {
        // No tools configured -> return undefined equivalents
        return XAIPreparedTools(tools: nil, toolChoice: nil, warnings: warnings)
    }

    var xaiTools: [JSONValue] = []

    for tool in normalizedTools {
        switch tool {
        case .provider(let providerTool):
            warnings.append(.unsupported(feature: "provider-defined tool \(providerTool.name)", details: nil))
        case .function(let functionTool):
            var functionPayload: [String: JSONValue] = [
                "name": .string(functionTool.name),
                "parameters": functionTool.inputSchema
            ]
            if let description = functionTool.description {
                functionPayload["description"] = .string(description)
            }

            xaiTools.append(
                .object([
                    "type": .string("function"),
                    "function": .object(functionPayload)
                ])
            )
        }
    }

    let resolvedTools = xaiTools.isEmpty ? nil : xaiTools

    let resolvedChoice: JSONValue?
    if let toolChoice {
        switch toolChoice {
        case .auto:
            resolvedChoice = .string("auto")
        case .none:
            resolvedChoice = .string("none")
        case .required:
            resolvedChoice = .string("required")
        case .tool(let name):
            resolvedChoice = .object([
                "type": .string("function"),
                "function": .object(["name": .string(name)])
            ])
        }
    } else {
        resolvedChoice = nil
    }

    return XAIPreparedTools(tools: resolvedTools, toolChoice: resolvedChoice, warnings: warnings)
}
