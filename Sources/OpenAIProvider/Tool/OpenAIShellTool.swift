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
        public let stdout: String
        public let stderr: String
        public let outcome: OpenAIShellOutcome
    }

    public let output: [Item]
}

public enum OpenAIShellOutcome: Codable, Sendable, Equatable {
    case timeout
    case exit(exitCode: Double)

    private enum CodingKeys: String, CodingKey {
        case type
        case exitCode
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "timeout":
            self = .timeout
        case "exit":
            let exitCode = try container.decode(Double.self, forKey: .exitCode)
            self = .exit(exitCode: exitCode)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown shell outcome type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .timeout:
            try container.encode("timeout", forKey: .type)
        case .exit(let exitCode):
            try container.encode("exit", forKey: .type)
            try container.encode(exitCode, forKey: .exitCode)
        }
    }
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
