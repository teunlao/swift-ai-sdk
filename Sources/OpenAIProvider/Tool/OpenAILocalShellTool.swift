import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct OpenAILocalShellAction: Codable, Sendable, Equatable {
    public let type: String
    public let command: [String]
    public let timeoutMs: Double?
    public let user: String?
    public let workingDirectory: String?
    public let env: [String: String]?

    enum CodingKeys: String, CodingKey {
        case type
        case command
        case timeoutMs = "timeout_ms"
        case user
        case workingDirectory = "working_directory"
        case env
    }
}

public struct OpenAILocalShellInput: Codable, Sendable, Equatable {
    public let action: OpenAILocalShellAction
}

public struct OpenAILocalShellOutput: Codable, Sendable, Equatable {
    public let output: String
}

private let localShellInputJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "required": .array([.string("action")]),
    "additionalProperties": .bool(false),
    "properties": .object([
        "action": .object([
            "type": .string("object"),
            "required": .array([.string("type"), .string("command")]),
            "additionalProperties": .bool(false),
            "properties": .object([
                "type": .object([
                    "type": .string("string"),
                    "enum": .array([JSONValue.string("exec")])
                ]),
                "command": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string")])
                ]),
                "timeout_ms": .object([
                    "type": .array([.string("number"), .string("null")])
                ]),
                "user": .object([
                    "type": .array([.string("string"), .string("null")])
                ]),
                "working_directory": .object([
                    "type": .array([.string("string"), .string("null")])
                ]),
                "env": .object([
                    "type": .array([.string("object"), .string("null")]),
                    "additionalProperties": .object(["type": .string("string")])
                ])
            ])
        ])
    ])
])

private let localShellOutputJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "required": .array([.string("output")]),
    "additionalProperties": .bool(false),
    "properties": .object([
        "output": .object([
            "type": .string("string")
        ])
    ])
])

public let openaiLocalShellInputSchema = FlexibleSchema(
    Schema.codable(OpenAILocalShellInput.self, jsonSchema: localShellInputJSONSchema)
)

public let openaiLocalShellOutputSchema = FlexibleSchema(
    Schema.codable(OpenAILocalShellOutput.self, jsonSchema: localShellOutputJSONSchema)
)

public let openaiLocalShellTool = createProviderToolFactoryWithOutputSchema(
    id: "openai.local_shell",
    name: "local_shell",
    inputSchema: FlexibleSchema(jsonSchema(localShellInputJSONSchema)),
    outputSchema: FlexibleSchema(jsonSchema(localShellOutputJSONSchema))
)
