import Foundation
import AISDKProvider

struct OpenAIChatPreparedTools {
    let tools: JSONValue?
    let toolChoice: JSONValue?
    let warnings: [SharedV3Warning]
}

enum OpenAIChatToolPreparer {
    static func prepare(
        tools: [LanguageModelV3Tool]?,
        toolChoice: LanguageModelV3ToolChoice?
    ) -> OpenAIChatPreparedTools {
        guard let tools, !tools.isEmpty else {
            return OpenAIChatPreparedTools(tools: nil, toolChoice: nil, warnings: [])
        }

        var warnings: [SharedV3Warning] = []
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

                if let strict = function.strict {
                    functionObject["strict"] = .bool(strict)
                }

                preparedTools.append(.object([
                    "type": .string("function"),
                    "function": .object(functionObject)
                ]))

            case .provider(let providerTool):
                warnings.append(.unsupported(feature: "provider-defined tool \(providerTool.id)", details: nil))
            }
        }

        let toolChoiceValue: JSONValue? = if let toolChoice {
            switch toolChoice {
            case .auto:
                .string("auto")
            case .none:
                .string("none")
            case .required:
                .string("required")
            case .tool(let toolName):
                .object([
                    "type": .string("function"),
                    "function": .object([
                        "name": .string(toolName)
                    ])
                ])
            }
        } else {
            nil
        }

        return OpenAIChatPreparedTools(
            tools: .array(preparedTools),
            toolChoice: toolChoiceValue,
            warnings: warnings
        )
    }
}
