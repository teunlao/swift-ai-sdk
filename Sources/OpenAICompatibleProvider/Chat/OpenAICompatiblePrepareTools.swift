import Foundation
import AISDKProvider

struct OpenAICompatiblePreparedTools {
    let tools: JSONValue?
    let toolChoice: JSONValue?
    let warnings: [LanguageModelV3CallWarning]
}

enum OpenAICompatibleToolPreparer {
    static func prepare(
        tools: [LanguageModelV3Tool]?,
        toolChoice: LanguageModelV3ToolChoice?
    ) -> OpenAICompatiblePreparedTools {
        guard let tools, !tools.isEmpty else {
            return OpenAICompatiblePreparedTools(tools: nil, toolChoice: nil, warnings: [])
        }

        var warnings: [LanguageModelV3CallWarning] = []
        var prepared: [JSONValue] = []

        for tool in tools {
            switch tool {
            case .function(let function):
                var functionObject: [String: JSONValue] = [
                    "name": .string(function.name),
                    "parameters": function.inputSchema
                ]

                if let description = function.description {
                    functionObject["description"] = .string(description)
                }

                prepared.append(.object([
                    "type": .string("function"),
                    "function": .object(functionObject)
                ]))

            case .providerDefined:
                warnings.append(.unsupportedTool(tool: tool, details: nil))
            }
        }

        let toolChoiceValue: JSONValue?
        if let toolChoice {
            switch toolChoice {
            case .auto:
                toolChoiceValue = .string("auto")
            case .none:
                toolChoiceValue = .string("none")
            case .required:
                toolChoiceValue = .string("required")
            case .tool(let name):
                toolChoiceValue = .object([
                    "type": .string("function"),
                    "function": .object(["name": .string(name)])
                ])
            }
        } else {
            toolChoiceValue = nil
        }

        return OpenAICompatiblePreparedTools(
            tools: prepared.isEmpty ? nil : .array(prepared),
            toolChoice: toolChoiceValue,
            warnings: warnings
        )
    }
}
