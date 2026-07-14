import Foundation
import AISDKProvider

struct OpenAICompatiblePreparedTools {
    let tools: JSONValue?
    let toolChoice: JSONValue?
    let warnings: [SharedV3Warning]
}

struct OpenAICompatiblePreparedToolsV4 {
    let tools: JSONValue?
    let toolChoice: JSONValue?
    let warnings: [SharedV4Warning]
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

            case .provider(let providerTool):
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

    static func prepare(
        tools: [LanguageModelV4Tool]?,
        toolChoice: LanguageModelV4ToolChoice?
    ) -> OpenAICompatiblePreparedToolsV4 {
        guard let tools, !tools.isEmpty else {
            return OpenAICompatiblePreparedToolsV4(tools: nil, toolChoice: nil, warnings: [])
        }

        var warnings: [SharedV4Warning] = []
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

            case .provider(let providerTool):
                warnings.append(.unsupported(
                    feature: "provider-defined tool \(providerTool.id)",
                    details: nil
                ))
            }
        }

        let toolChoiceValue: JSONValue?
        switch toolChoice {
        case .some(.auto):
            toolChoiceValue = .string("auto")
        case .some(.none):
            toolChoiceValue = .string("none")
        case .some(.required):
            toolChoiceValue = .string("required")
        case .some(.tool(let toolName)):
            toolChoiceValue = .object([
                "type": .string("function"),
                "function": .object(["name": .string(toolName)])
            ])
        case nil:
            toolChoiceValue = nil
        }

        return OpenAICompatiblePreparedToolsV4(
            tools: .array(prepared),
            toolChoice: toolChoiceValue,
            warnings: warnings
        )
    }
}
