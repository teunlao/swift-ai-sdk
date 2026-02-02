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
    public let content: [OutputFile]

    public struct OutputFile: Codable, Equatable, Sendable {
        public let type: String
        public let fileId: String

        enum CodingKeys: String, CodingKey {
            case type
            case fileId = "file_id"
        }
    }

    enum CodingKeys: String, CodingKey {
        case type
        case stdout
        case stderr
        case returnCode = "return_code"
        case content
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        stdout = try container.decode(String.self, forKey: .stdout)
        stderr = try container.decode(String.self, forKey: .stderr)
        returnCode = try container.decode(Int.self, forKey: .returnCode)
        content = try container.decodeIfPresent([OutputFile].self, forKey: .content) ?? []
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
