import Foundation
import AISDKProvider

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/huggingface/src/responses/huggingface-responses-prepare-tools.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

struct HuggingFacePreparedTools {
    let tools: JSONValue?
    let toolChoice: JSONValue?
    let warnings: [LanguageModelV3CallWarning]
}

func prepareHuggingFaceResponsesTools(
    tools: [LanguageModelV3Tool]?,
    toolChoice: LanguageModelV3ToolChoice?
) -> HuggingFacePreparedTools {
    let normalizedTools = tools?.isEmpty == false ? tools : nil
    var warnings: [LanguageModelV3CallWarning] = []

    guard let normalizedTools else {
        return HuggingFacePreparedTools(tools: nil, toolChoice: nil, warnings: warnings)
    }

    var huggingfaceTools: [JSONValue] = []

    for tool in normalizedTools {
        switch tool {
        case .function(let functionTool):
            var object: [String: JSONValue] = [
                "type": .string("function"),
                "name": .string(functionTool.name),
                "parameters": functionTool.inputSchema
            ]
            if let description = functionTool.description {
                object["description"] = .string(description)
            }
            huggingfaceTools.append(.object(object))

        case .providerDefined:
            warnings.append(.unsupportedTool(tool: tool, details: nil))
            continue
        }
    }

    let toolsValue: JSONValue? = huggingfaceTools.isEmpty ? nil : .array(huggingfaceTools)

    var mappedToolChoice: JSONValue? = nil
    if let toolChoice {
        switch toolChoice {
        case .auto:
            mappedToolChoice = .string("auto")
        case .required:
            mappedToolChoice = .string("required")
        case .none:
            mappedToolChoice = nil
        case .tool(let toolName):
            mappedToolChoice = .object([
                "type": .string("function"),
                "function": .object(["name": .string(toolName)])
            ])
        }
    }

    return HuggingFacePreparedTools(tools: toolsValue, toolChoice: mappedToolChoice, warnings: warnings)
}
