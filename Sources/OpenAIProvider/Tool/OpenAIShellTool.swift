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

public struct OpenAIShellArgs: Sendable, Equatable {
    public let environment: [String: JSONValue]?

    public init(environment: [String: JSONValue]? = nil) {
        self.environment = environment
    }
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

private let shellArgsJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "additionalProperties": .bool(true),
    "properties": .object([
        "environment": .object([
            "type": .array([.string("object"), .string("null")])
        ])
    ])
])

public let openaiShellInputSchema = FlexibleSchema(
    Schema.codable(OpenAIShellInput.self, jsonSchema: shellInputJSONSchema)
)

public let openaiShellOutputSchema = FlexibleSchema(
    Schema.codable(OpenAIShellOutput.self, jsonSchema: shellOutputJSONSchema)
)

public let openaiShellArgsSchema = FlexibleSchema<OpenAIShellArgs>(
    Schema(
        jsonSchemaResolver: { shellArgsJSONSchema },
        validator: { value in
            do {
                let json = try jsonValue(from: value)
                guard case .object(let dict) = json else {
                    let error = SchemaValidationIssuesError(vendor: "openai", issues: "expected object")
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                var environment: [String: JSONValue]?
                if let environmentValue = dict["environment"], environmentValue != .null {
                    guard case .object(let environmentObject) = environmentValue else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "environment must be an object")
                        return .failure(error: TypeValidationError.wrap(value: environmentValue, cause: error))
                    }
                    guard isValidShellEnvironment(environmentObject) else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "invalid shell environment")
                        return .failure(error: TypeValidationError.wrap(value: environmentValue, cause: error))
                    }
                    environment = environmentObject
                }

                return .success(value: OpenAIShellArgs(environment: environment))
            } catch let error as TypeValidationError {
                return .failure(error: error)
            } catch {
                return .failure(error: TypeValidationError.wrap(value: value, cause: error))
            }
        }
    )
)

public let openaiShellTool = createProviderToolFactoryWithOutputSchema(
    id: "openai.shell",
    name: "shell",
    inputSchema: FlexibleSchema(jsonSchema(shellInputJSONSchema)),
    outputSchema: FlexibleSchema(jsonSchema(shellOutputJSONSchema))
)

private func isValidShellEnvironment(_ environment: [String: JSONValue]) -> Bool {
    let type = environment["type"]?.stringValue ?? "local"

    switch type {
    case "containerReference":
        guard let containerId = environment["containerId"], case .string(let value) = containerId else {
            return false
        }
        return !value.isEmpty

    case "containerAuto":
        if let fileIds = environment["fileIds"], fileIds != .null {
            guard case .array(let entries) = fileIds,
                  entries.allSatisfy({ entry in
                      if case .string = entry { return true }
                      return false
                  }) else {
                return false
            }
        }

        if let memoryLimit = environment["memoryLimit"], memoryLimit != .null {
            guard case .string(let value) = memoryLimit,
                  ["1g", "4g", "16g", "64g"].contains(value) else {
                return false
            }
        }

        if let networkPolicy = environment["networkPolicy"], networkPolicy != .null {
            guard case .object(let policy) = networkPolicy,
                  let policyType = policy["type"]?.stringValue else {
                return false
            }

            switch policyType {
            case "disabled":
                break
            case "allowlist":
                guard let allowedDomains = policy["allowedDomains"], case .array(let domains) = allowedDomains,
                      domains.allSatisfy({ domain in
                          if case .string = domain { return true }
                          return false
                      }) else {
                    return false
                }

                if let domainSecrets = policy["domainSecrets"], domainSecrets != .null {
                    guard case .array(let secrets) = domainSecrets else {
                        return false
                    }

                    let validSecrets = secrets.allSatisfy { secret in
                        guard case .object(let object) = secret,
                              case .string = object["domain"],
                              case .string = object["name"],
                              case .string = object["value"] else {
                            return false
                        }
                        return true
                    }
                    if !validSecrets { return false }
                }
            default:
                return false
            }
        }

        if let skills = environment["skills"], skills != .null {
            guard case .array(let entries) = skills else {
                return false
            }

            let validSkills = entries.allSatisfy { skill in
                guard case .object(let object) = skill,
                      let skillType = object["type"]?.stringValue else {
                    return false
                }

                switch skillType {
                case "skillReference":
                    guard case .string? = object["skillId"] else { return false }
                    if let version = object["version"], version != .null {
                        guard case .string = version else { return false }
                    }
                    return true

                case "inline":
                    guard case .string? = object["name"],
                          case .string? = object["description"],
                          case .object(let source)? = object["source"],
                          source["type"] == .string("base64"),
                          source["mediaType"] == .string("application/zip"),
                          case .string? = source["data"] else {
                        return false
                    }
                    return true

                default:
                    return false
                }
            }

            if !validSkills { return false }
        }

        return true

    case "local":
        if let skills = environment["skills"], skills != .null {
            guard case .array(let entries) = skills else {
                return false
            }

            return entries.allSatisfy { entry in
                guard case .object(let object) = entry,
                      case .string? = object["name"],
                      case .string? = object["description"],
                      case .string? = object["path"] else {
                    return false
                }
                return true
            }
        }
        return true

    default:
        return false
    }
}

private extension JSONValue {
    var stringValue: String? {
        if case .string(let value) = self {
            return value
        }
        return nil
    }
}
