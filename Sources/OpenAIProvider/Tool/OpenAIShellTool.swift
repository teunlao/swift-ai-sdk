import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct OpenAIShellInput: Codable, Sendable, Equatable {
    public struct Action: Codable, Sendable, Equatable {
        public let commands: [String]
        public let timeoutMs: Double?
        public let maxOutputLength: Double?
    }

    public let action: Action
}

public struct OpenAIShellOutput: Codable, Sendable, Equatable {
    public struct Item: Codable, Sendable, Equatable {
        public struct Outcome: Codable, Sendable, Equatable {
            public let type: String
            public let exitCode: Double?
        }

        public let stdout: String
        public let stderr: String
        public let outcome: Outcome
    }

    public let output: [Item]
}

private let shellInputJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "required": .array([.string("action")]),
    "additionalProperties": .bool(false),
    "properties": .object([
        "action": .object([
            "type": .string("object"),
            "required": .array([.string("commands")]),
            "additionalProperties": .bool(false),
            "properties": .object([
                "commands": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string")])
                ]),
                "timeoutMs": .object([
                    "type": .array([.string("number"), .string("null")])
                ]),
                "maxOutputLength": .object([
                    "type": .array([.string("number"), .string("null")])
                ])
            ])
        ])
    ])
])

private let shellOutputJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "required": .array([.string("output")]),
    "additionalProperties": .bool(false),
    "properties": .object([
        "output": .object([
            "type": .string("array"),
            "items": .object([
                "type": .string("object"),
                "required": .array([.string("stdout"), .string("stderr"), .string("outcome")]),
                "additionalProperties": .bool(false),
                "properties": .object([
                    "stdout": .object([
                        "type": .string("string")
                    ]),
                    "stderr": .object([
                        "type": .string("string")
                    ]),
                    "outcome": .object([
                        "type": .string("object"),
                        "required": .array([.string("type")]),
                        "additionalProperties": .bool(false),
                        "properties": .object([
                            "type": .object([
                                "type": .string("string"),
                                "enum": .array([.string("timeout"), .string("exit")])
                            ]),
                            "exitCode": .object([
                                "type": .array([.string("number"), .string("null")])
                            ])
                        ])
                    ])
                ])
            ])
        ])
    ])
])

public let openaiShellInputSchema = FlexibleSchema(
    Schema.codable(OpenAIShellInput.self, jsonSchema: shellInputJSONSchema)
)

public let openaiShellOutputSchema = FlexibleSchema(
    Schema.codable(OpenAIShellOutput.self, jsonSchema: shellOutputJSONSchema)
)

public let openaiShellTool = createProviderDefinedToolFactoryWithOutputSchema(
    id: "openai.shell",
    name: "shell",
    inputSchema: FlexibleSchema(jsonSchema(shellInputJSONSchema)),
    outputSchema: FlexibleSchema(jsonSchema(shellOutputJSONSchema))
)

