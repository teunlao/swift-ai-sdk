import Foundation
import AISDKProvider

struct OpenAIChatPreparedTools {
    let tools: JSONValue?
    let toolChoice: JSONValue?
    let warnings: [LanguageModelV3CallWarning]
}

enum OpenAIChatToolPreparer {
    static func prepare(
        tools: [LanguageModelV3Tool]?,
        toolChoice: LanguageModelV3ToolChoice?,
        structuredOutputs: Bool,
        strictJsonSchema: Bool
    ) -> OpenAIChatPreparedTools {
        guard let tools, !tools.isEmpty else {
            return OpenAIChatPreparedTools(tools: nil, toolChoice: nil, warnings: [])
        }

        var warnings: [LanguageModelV3CallWarning] = []
        var preparedTools: [JSONValue] = []

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

                if structuredOutputs {
                    functionObject["strict"] = .bool(strictJsonSchema)
                }

                preparedTools.append(.object([
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
            case .tool(let toolName):
                toolChoiceValue = .object([
                    "type": .string("function"),
                    "function": .object([
                        "name": .string(toolName)
                    ])
                ])
            }
        } else {
            toolChoiceValue = nil
        }

        return OpenAIChatPreparedTools(
            tools: preparedTools.isEmpty ? nil : .array(preparedTools),
            toolChoice: toolChoiceValue,
            warnings: warnings
        )
    }
}
