import Foundation
import AISDKProvider

struct OpenAICompatiblePreparedTools {
    let tools: JSONValue?
    let toolChoice: JSONValue?
    let warnings: [SharedV3Warning]
}

enum OpenAICompatibleToolPreparer {
    static func prepare(
        tools: [LanguageModelV3Tool]?,
        toolChoice: LanguageModelV3ToolChoice?
    ) -> OpenAICompatiblePreparedTools {
        guard let tools, !tools.isEmpty else {
            return OpenAICompatiblePreparedTools(tools: nil, toolChoice: nil, warnings: [])
        }

        var warnings: [SharedV3Warning] = []
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
                if let strict = function.strict {
                    functionObject["strict"] = .bool(strict)
                }

                prepared.append(.object([
                    "type": .string("function"),
                    "function": .object(functionObject)
                ]))

            case .providerDefined(let providerTool):
                warnings.append(.unsupported(feature: "provider-defined tool \(providerTool.id)", details: nil))
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
