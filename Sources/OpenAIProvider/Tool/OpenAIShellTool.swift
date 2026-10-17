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

public struct OpenAIShellArgs: Codable, Sendable, Equatable {
    public let environment: [String: JSONValue]?
    public init(environment: [String: JSONValue]? = nil) { self.environment = environment }
}

public enum OpenAIShellOutcome: Codable, Sendable, Equatable {
    case timeout
    case exit(exitCode: Double)

    private enum CodingKeys: String, CodingKey { case type, exitCode }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "timeout": self = .timeout
        case "exit": self = .exit(exitCode: try container.decode(Double.self, forKey: .exitCode))
        default: throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown shell outcome type")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .timeout: try container.encode("timeout", forKey: .type)
        case .exit(let code):
            try container.encode("exit", forKey: .type)
            try container.encode(code, forKey: .exitCode)
        }
    }
}

private let shellStrings: JSONValue = .object(["type": .string("array"), "items": .object(["type": .string("string")])])
private let shellInputJSONSchema: JSONValue = .object([
    "type": .string("object"), "additionalProperties": .bool(false), "required": .array([.string("action")]),
    "properties": .object(["action": .object([
        "type": .string("object"), "additionalProperties": .bool(false), "required": .array([.string("commands")]),
        "properties": .object([
            "commands": shellStrings, "timeoutMs": .object(["type": .string("number")]), "maxOutputLength": .object(["type": .string("number")])
        ])
    ])])
])
private let shellOutputJSONSchema: JSONValue = .object([
    "type": .string("object"), "additionalProperties": .bool(false), "required": .array([.string("output")]),
    "properties": .object(["output": .object([
        "type": .string("array"), "items": .object([
            "type": .string("object"), "additionalProperties": .bool(false), "required": .array([.string("stdout"), .string("stderr"), .string("outcome")]),
            "properties": .object([
                "stdout": .object(["type": .string("string")]), "stderr": .object(["type": .string("string")]),
                "outcome": .object(["oneOf": .array([
                    .object(["type": .string("object"), "additionalProperties": .bool(false), "required": .array([.string("type")]),
                        "properties": .object(["type": .object(["enum": .array([.string("timeout")])])])]),
                    .object(["type": .string("object"), "additionalProperties": .bool(false), "required": .array([.string("type"), .string("exitCode")]),
                        "properties": .object(["type": .object(["enum": .array([.string("exit")])]), "exitCode": .object(["type": .string("number")])])])
                ])])
            ])
        ])
    ])])
])
private let shellSkillsSchema: JSONValue = .object([
    "type": .string("array"), "items": .object(["oneOf": .array([
        .object([
            "type": .string("object"), "additionalProperties": .bool(false), "required": .array([.string("type"), .string("providerReference")]),
            "properties": .object([
                "type": .object(["enum": .array([.string("skillReference")])]),
                "providerReference": .object(["type": .string("object"), "additionalProperties": .object(["type": .string("string")])]),
                "version": .object(["type": .string("string")])
            ])
        ]),
        .object([
            "type": .string("object"), "additionalProperties": .bool(false), "required": .array([.string("type"), .string("name"), .string("description"), .string("source")]),
            "properties": .object([
                "type": .object(["enum": .array([.string("inline")])]), "name": .object(["type": .string("string")]), "description": .object(["type": .string("string")]),
                "source": .object([
                    "type": .string("object"), "additionalProperties": .bool(false), "required": .array([.string("type"), .string("mediaType"), .string("data")]),
                    "properties": .object([
                        "type": .object(["enum": .array([.string("base64")])]), "mediaType": .object(["enum": .array([.string("application/zip")])]), "data": .object(["type": .string("string")])
                    ])
                ])
            ])
        ])
    ])])
])
private let shellArgsJSONSchema: JSONValue = .object([
    "type": .string("object"), "additionalProperties": .bool(false), "properties": .object(["environment": .object(["anyOf": .array([
        .object([
            "type": .string("object"), "additionalProperties": .bool(false), "required": .array([.string("type")]),
            "properties": .object([
                "type": .object(["enum": .array([.string("containerAuto")])]), "fileIds": shellStrings,
                "memoryLimit": .object(["enum": .array(["1g", "4g", "16g", "64g"].map(JSONValue.string))]), "skills": shellSkillsSchema,
                "networkPolicy": .object(["oneOf": .array([
                    .object(["type": .string("object"), "additionalProperties": .bool(false), "required": .array([.string("type")]), "properties": .object(["type": .object(["enum": .array([.string("disabled")])])])]),
                    .object([
                        "type": .string("object"), "additionalProperties": .bool(false), "required": .array([.string("type"), .string("allowedDomains")]),
                        "properties": .object([
                            "type": .object(["enum": .array([.string("allowlist")])]), "allowedDomains": shellStrings,
                            "domainSecrets": .object(["type": .string("array"), "items": .object([
                                "type": .string("object"), "additionalProperties": .bool(false), "required": .array([.string("domain"), .string("name"), .string("value")]),
                                "properties": .object(["domain": .object(["type": .string("string")]), "name": .object(["type": .string("string")]), "value": .object(["type": .string("string")])])
                            ])])
                        ])
                    ])
                ])])
            ])
        ]),
        .object([
            "type": .string("object"), "additionalProperties": .bool(false), "required": .array([.string("type"), .string("containerId")]),
            "properties": .object(["type": .object(["enum": .array([.string("containerReference")])]), "containerId": .object(["type": .string("string")])])
        ]),
        .object([
            "type": .string("object"), "additionalProperties": .bool(false), "properties": .object([
                "type": .object(["enum": .array([.string("local")])]), "skills": .object(["type": .string("array"), "items": .object([
                    "type": .string("object"), "additionalProperties": .bool(false), "required": .array([.string("name"), .string("description"), .string("path")]),
                    "properties": .object(["name": .object(["type": .string("string")]), "description": .object(["type": .string("string")]), "path": .object(["type": .string("string")])])
                ])])
            ])
        ])
    ])])])
])

public let openaiShellInputSchema = openAIToolSchema(OpenAIShellInput.self, shellInputJSONSchema)
public let openaiShellOutputSchema = openAIToolSchema(OpenAIShellOutput.self, shellOutputJSONSchema)
public let openaiShellArgsSchema = openAIToolSchema(OpenAIShellArgs.self, shellArgsJSONSchema)
public let openaiShellTool = createProviderDefinedToolFactoryWithOutputSchema(
    id: "openai.shell", name: "shell", inputSchema: openAIToolSchema(shellInputJSONSchema), outputSchema: openAIToolSchema(shellOutputJSONSchema)
)
public let openaiShellToolFactory: @Sendable (OpenAIShellArgs) -> Tool = { args in
    var options = ProviderDefinedToolFactoryWithOutputSchemaOptions()
    options.args["environment"] = args.environment.map(JSONValue.object)
    return openaiShellTool(options)
}
