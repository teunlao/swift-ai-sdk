import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct AnthropicCodeExecutionOptions: Sendable, Equatable {
    public init() {}
}

private let anthropicCodeExecutionInputSchema = FlexibleSchema(
    jsonSchema(
        .object([
            "type": .string("object"),
            "properties": .object([
                "code": .object(["type": .string("string")])
            ]),
            "required": .array([.string("code")]),
            "additionalProperties": .bool(false)
        ])
    )
)

public struct AnthropicCodeExecutionToolResult: Codable, Equatable, Sendable {
    public let type: String
    public let stdout: String
    public let stderr: String
    public let returnCode: Int

    enum CodingKeys: String, CodingKey {
        case type
        case stdout
        case stderr
        case returnCode = "return_code"
    }
}

public let anthropicCodeExecution20250522OutputSchema = FlexibleSchema(
    Schema<AnthropicCodeExecutionToolResult>.codable(
        AnthropicCodeExecutionToolResult.self,
        jsonSchema: .object(["type": .string("object")])
    )
)

private let anthropicCodeExecution20250522ToolOutputSchema = FlexibleSchema(
    jsonSchema(.object(["type": .string("object")]))
)

private let anthropicCodeExecutionFactory = createProviderDefinedToolFactoryWithOutputSchema(
    id: "anthropic.code_execution_20250522",
    name: "code_execution",
    inputSchema: anthropicCodeExecutionInputSchema,
    outputSchema: anthropicCodeExecution20250522ToolOutputSchema
)

@discardableResult
public func anthropicCodeExecution20250522() -> Tool {
    anthropicCodeExecutionFactory(ProviderDefinedToolFactoryWithOutputSchemaOptions(args: [:]))
}
