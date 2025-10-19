import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct AnthropicTextEditor20250728Args: Codable, Sendable, Equatable {
    public var maxCharacters: Int?

    public init(maxCharacters: Int? = nil) {
        self.maxCharacters = maxCharacters
    }

}

public let anthropicTextEditor20250728ArgsSchema = FlexibleSchema(
    Schema<AnthropicTextEditor20250728Args>.codable(
        AnthropicTextEditor20250728Args.self,
        jsonSchema: .object([
            "type": .string("object")
        ])
    )
)

private let anthropicTextEditor20250728InputSchema = FlexibleSchema(
    Schema<JSONValue>.codable(
        JSONValue.self,
        jsonSchema: .object([
            "type": .string("object")
        ])
    )
)

public let anthropicTextEditor20250728: @Sendable (AnthropicTextEditor20250728Args) -> Tool =
    createProviderDefinedToolFactory(
        id: "anthropic.text_editor_20250728",
        name: "str_replace_based_edit_tool",
        inputSchema: anthropicTextEditor20250728InputSchema
    ) { options in
        var args: [String: JSONValue] = [:]
        if let maxCharacters = options.maxCharacters {
            args["max_characters"] = .number(Double(maxCharacters))
        }
        return ProviderDefinedToolFactoryOptions(args: args)
    }
