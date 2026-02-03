import Foundation
import AISDKProvider
import AISDKProviderUtils

public enum OpenAIMCPAllowedTools: Sendable, Equatable {
    public struct Filter: Sendable, Equatable {
        public let readOnly: Bool?
        public let toolNames: [String]?

        public init(readOnly: Bool? = nil, toolNames: [String]? = nil) {
            self.readOnly = readOnly
            self.toolNames = toolNames
        }
    }

    case toolNames([String])
    case filter(Filter)
}

public enum OpenAIMCPRequireApproval: Sendable, Equatable {
    public struct NeverFilter: Sendable, Equatable {
        public let toolNames: [String]?

        public init(toolNames: [String]? = nil) {
            self.toolNames = toolNames
        }
    }

    public struct Conditional: Sendable, Equatable {
        public let never: NeverFilter?

        public init(never: NeverFilter? = nil) {
            self.never = never
        }
    }

    case always
    case never
    case conditional(Conditional)
}

public struct OpenAIMCPArgs: Sendable, Equatable {
    public let serverLabel: String
    public let allowedTools: OpenAIMCPAllowedTools?
    public let authorization: String?
    public let connectorId: String?
    public let headers: [String: String]?
    public let requireApproval: OpenAIMCPRequireApproval?
    public let serverDescription: String?
    public let serverUrl: String?

    public init(
        serverLabel: String,
        allowedTools: OpenAIMCPAllowedTools? = nil,
        authorization: String? = nil,
        connectorId: String? = nil,
        headers: [String: String]? = nil,
        requireApproval: OpenAIMCPRequireApproval? = nil,
        serverDescription: String? = nil,
        serverUrl: String? = nil
    ) {
        self.serverLabel = serverLabel
        self.allowedTools = allowedTools
        self.authorization = authorization
        self.connectorId = connectorId
        self.headers = headers
        self.requireApproval = requireApproval
        self.serverDescription = serverDescription
        self.serverUrl = serverUrl
    }
}

private let mcpArgsJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "additionalProperties": .bool(false),
    "required": .array([.string("serverLabel")]),
    "properties": .object([
        "serverLabel": .object(["type": .string("string")]),
        "allowedTools": .object([
            "type": .array([.string("array"), .string("object"), .string("null")])
        ]),
        "authorization": .object([
            "type": .array([.string("string"), .string("null")])
        ]),
        "connectorId": .object([
            "type": .array([.string("string"), .string("null")])
        ]),
        "headers": .object([
            "type": .array([.string("object"), .string("null")])
        ]),
        "requireApproval": .object([
            "type": .array([.string("string"), .string("object"), .string("null")])
        ]),
        "serverDescription": .object([
            "type": .array([.string("string"), .string("null")])
        ]),
        "serverUrl": .object([
            "type": .array([.string("string"), .string("null")])
        ])
    ])
])

public let openaiMcpArgsSchema = FlexibleSchema<OpenAIMCPArgs>(
    Schema(
        jsonSchemaResolver: { mcpArgsJSONSchema },
        validator: { value in
            do {
                let json = try jsonValue(from: value)
                guard case .object(let dict) = json else {
                    let error = SchemaValidationIssuesError(vendor: "openai", issues: "expected object")
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                guard case .string(let serverLabel) = dict["serverLabel"] else {
                    let error = SchemaValidationIssuesError(vendor: "openai", issues: "serverLabel must be a string")
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                func optionalString(_ key: String) throws -> String? {
                    guard let raw = dict[key], raw != .null else { return nil }
                    guard case .string(let string) = raw else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "\(key) must be a string")
                        throw TypeValidationError.wrap(value: raw, cause: error)
                    }
                    return string
                }

                let authorization = try optionalString("authorization")
                let connectorId = try optionalString("connectorId")
                let serverDescription = try optionalString("serverDescription")
                let serverUrl = try optionalString("serverUrl")

                var headers: [String: String]? = nil
                if let rawHeaders = dict["headers"], rawHeaders != .null {
                    guard case .object(let headerObject) = rawHeaders else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "headers must be an object")
                        return .failure(error: TypeValidationError.wrap(value: rawHeaders, cause: error))
                    }

                    var parsedHeaders: [String: String] = [:]
                    for (key, value) in headerObject {
                        guard case .string(let string) = value else {
                            let error = SchemaValidationIssuesError(vendor: "openai", issues: "headers values must be strings")
                            return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                        }
                        parsedHeaders[key] = string
                    }
                    headers = parsedHeaders
                }

                var allowedTools: OpenAIMCPAllowedTools? = nil
                if let rawAllowedTools = dict["allowedTools"], rawAllowedTools != .null {
                    switch rawAllowedTools {
                    case .array(let array):
                        let names = try array.map { element -> String in
                            guard case .string(let name) = element else {
                                let error = SchemaValidationIssuesError(vendor: "openai", issues: "allowedTools must contain strings")
                                throw TypeValidationError.wrap(value: element, cause: error)
                            }
                            return name
                        }
                        allowedTools = .toolNames(names)
                    case .object(let object):
                        var readOnly: Bool? = nil
                        if let rawReadOnly = object["readOnly"], rawReadOnly != .null {
                            guard case .bool(let value) = rawReadOnly else {
                                let error = SchemaValidationIssuesError(vendor: "openai", issues: "allowedTools.readOnly must be a boolean")
                                return .failure(error: TypeValidationError.wrap(value: rawReadOnly, cause: error))
                            }
                            readOnly = value
                        }

                        var toolNames: [String]? = nil
                        if let rawToolNames = object["toolNames"], rawToolNames != .null {
                            guard case .array(let array) = rawToolNames else {
                                let error = SchemaValidationIssuesError(vendor: "openai", issues: "allowedTools.toolNames must be an array")
                                return .failure(error: TypeValidationError.wrap(value: rawToolNames, cause: error))
                            }
                            toolNames = try array.map { element -> String in
                                guard case .string(let name) = element else {
                                    let error = SchemaValidationIssuesError(vendor: "openai", issues: "allowedTools.toolNames must contain strings")
                                    throw TypeValidationError.wrap(value: element, cause: error)
                                }
                                return name
                            }
                        }

                        allowedTools = .filter(OpenAIMCPAllowedTools.Filter(readOnly: readOnly, toolNames: toolNames))
                    default:
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "allowedTools must be an array or object")
                        return .failure(error: TypeValidationError.wrap(value: rawAllowedTools, cause: error))
                    }
                }

                var requireApproval: OpenAIMCPRequireApproval? = nil
                if let rawRequireApproval = dict["requireApproval"], rawRequireApproval != .null {
                    switch rawRequireApproval {
                    case .string(let value):
                        switch value {
                        case "always":
                            requireApproval = .always
                        case "never":
                            requireApproval = .never
                        default:
                            let error = SchemaValidationIssuesError(vendor: "openai", issues: "requireApproval must be 'always' or 'never'")
                            return .failure(error: TypeValidationError.wrap(value: rawRequireApproval, cause: error))
                        }
                    case .object(let object):
                        var neverFilter: OpenAIMCPRequireApproval.NeverFilter? = nil
                        if let rawNever = object["never"], rawNever != .null {
                            guard case .object(let neverObject) = rawNever else {
                                let error = SchemaValidationIssuesError(vendor: "openai", issues: "requireApproval.never must be an object")
                                return .failure(error: TypeValidationError.wrap(value: rawNever, cause: error))
                            }

                            var toolNames: [String]? = nil
                            if let rawToolNames = neverObject["toolNames"], rawToolNames != .null {
                                guard case .array(let array) = rawToolNames else {
                                    let error = SchemaValidationIssuesError(vendor: "openai", issues: "requireApproval.never.toolNames must be an array")
                                    return .failure(error: TypeValidationError.wrap(value: rawToolNames, cause: error))
                                }
                                toolNames = try array.map { element -> String in
                                    guard case .string(let name) = element else {
                                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "requireApproval.never.toolNames must contain strings")
                                        throw TypeValidationError.wrap(value: element, cause: error)
                                    }
                                    return name
                                }
                            }

                            neverFilter = OpenAIMCPRequireApproval.NeverFilter(toolNames: toolNames)
                        }

                        requireApproval = .conditional(OpenAIMCPRequireApproval.Conditional(never: neverFilter))
                    default:
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "requireApproval must be a string or object")
                        return .failure(error: TypeValidationError.wrap(value: rawRequireApproval, cause: error))
                    }
                }

                if serverUrl == nil && connectorId == nil {
                    let error = SchemaValidationIssuesError(vendor: "openai", issues: "One of serverUrl or connectorId must be provided.")
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                let args = OpenAIMCPArgs(
                    serverLabel: serverLabel,
                    allowedTools: allowedTools,
                    authorization: authorization,
                    connectorId: connectorId,
                    headers: headers,
                    requireApproval: requireApproval,
                    serverDescription: serverDescription,
                    serverUrl: serverUrl
                )

                return .success(value: args)
            } catch let error as TypeValidationError {
                return .failure(error: error)
            } catch {
                let wrapped = TypeValidationError.wrap(value: value, cause: error)
                return .failure(error: wrapped)
            }
        }
    )
)

private let mcpInputJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "additionalProperties": .bool(true)
])

private let mcpOutputJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "additionalProperties": .bool(false),
    "required": .array([.string("type"), .string("serverLabel"), .string("name"), .string("arguments")]),
    "properties": .object([
        "type": .object([
            "type": .string("string"),
            "enum": .array([.string("call")])
        ]),
        "serverLabel": .object(["type": .string("string")]),
        "name": .object(["type": .string("string")]),
        "arguments": .object(["type": .string("string")]),
        "output": .object([
            "type": .array([.string("string"), .string("null")])
        ]),
        "error": .object([
            "type": .array([
                .string("string"),
                .string("number"),
                .string("boolean"),
                .string("null"),
                .string("array"),
                .string("object")
            ])
        ])
    ])
])

public let openaiMcpToolFactory = createProviderToolFactoryWithOutputSchema(
    id: "openai.mcp",
    name: "mcp",
    inputSchema: FlexibleSchema(jsonSchema(mcpInputJSONSchema)),
    outputSchema: FlexibleSchema(jsonSchema(mcpOutputJSONSchema))
) { (args: OpenAIMCPArgs) in
    var options = ProviderToolFactoryWithOutputSchemaOptions()
    options.args = encodeOpenAIMCPArgs(args)
    return options
}

private func encodeOpenAIMCPArgs(_ args: OpenAIMCPArgs) -> [String: JSONValue] {
    var payload: [String: JSONValue] = [
        "serverLabel": .string(args.serverLabel)
    ]

    if let allowedTools = args.allowedTools {
        switch allowedTools {
        case .toolNames(let names):
            payload["allowedTools"] = .array(names.map(JSONValue.string))
        case .filter(let filter):
            var filterPayload: [String: JSONValue] = [:]
            if let readOnly = filter.readOnly {
                filterPayload["readOnly"] = .bool(readOnly)
            }
            if let toolNames = filter.toolNames {
                filterPayload["toolNames"] = .array(toolNames.map(JSONValue.string))
            }
            payload["allowedTools"] = .object(filterPayload)
        }
    }

    if let authorization = args.authorization {
        payload["authorization"] = .string(authorization)
    }
    if let connectorId = args.connectorId {
        payload["connectorId"] = .string(connectorId)
    }
    if let headers = args.headers {
        payload["headers"] = .object(headers.mapValues(JSONValue.string))
    }
    if let requireApproval = args.requireApproval {
        payload["requireApproval"] = encodeRequireApproval(requireApproval)
    }
    if let serverDescription = args.serverDescription {
        payload["serverDescription"] = .string(serverDescription)
    }
    if let serverUrl = args.serverUrl {
        payload["serverUrl"] = .string(serverUrl)
    }

    return payload
}

private func encodeRequireApproval(_ value: OpenAIMCPRequireApproval) -> JSONValue {
    switch value {
    case .always:
        return .string("always")
    case .never:
        return .string("never")
    case .conditional(let conditional):
        guard let never = conditional.never else {
            return .object([:])
        }
        var neverPayload: [String: JSONValue] = [:]
        if let toolNames = never.toolNames {
            neverPayload["toolNames"] = .array(toolNames.map(JSONValue.string))
        }
        return .object([
            "never": .object(neverPayload)
        ])
    }
}
