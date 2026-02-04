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

private let anthropicCodeExecution20250522OutputJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "properties": .object([
        "type": .object(["const": .string("code_execution_result")]),
        "stdout": .object(["type": .string("string")]),
        "stderr": .object(["type": .string("string")]),
        "return_code": .object(["type": .string("number")]),
        "content": .object([
            "type": .string("array"),
            "items": .object([
                "type": .string("object"),
                "properties": .object([
                    "type": .object(["const": .string("code_execution_output")]),
                    "file_id": .object(["type": .string("string")]),
                ]),
                "required": .array([.string("type"), .string("file_id")]),
                "additionalProperties": .bool(false),
            ]),
        ]),
    ]),
    "required": .array([.string("type"), .string("stdout"), .string("stderr"), .string("return_code")]),
    "additionalProperties": .bool(false),
])

public let anthropicCodeExecution20250522OutputSchema = FlexibleSchema(
    Schema<AnthropicCodeExecutionToolResult>.codable(
        AnthropicCodeExecutionToolResult.self,
        jsonSchema: anthropicCodeExecution20250522OutputJSONSchema
    )
)

private let anthropicCodeExecution20250522ToolOutputSchema = FlexibleSchema(
    jsonSchema(anthropicCodeExecution20250522OutputJSONSchema)
)

private let anthropicCodeExecutionFactory = createProviderToolFactoryWithOutputSchema(
    id: "anthropic.code_execution_20250522",
    name: "code_execution",
    inputSchema: anthropicCodeExecutionInputSchema,
    outputSchema: anthropicCodeExecution20250522ToolOutputSchema
)

@discardableResult
public func anthropicCodeExecution20250522() -> Tool {
    anthropicCodeExecutionFactory(ProviderToolFactoryWithOutputSchemaOptions(args: [:]))
}
