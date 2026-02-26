import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct XAIMCPServerArgs: Sendable, Equatable {
    public var serverUrl: String
    public var serverLabel: String?
    public var serverDescription: String?
    public var allowedTools: [String]?
    public var headers: [String: String]?
    public var authorization: String?

    public init(
        serverUrl: String,
        serverLabel: String? = nil,
        serverDescription: String? = nil,
        allowedTools: [String]? = nil,
        headers: [String: String]? = nil,
        authorization: String? = nil
    ) {
        self.serverUrl = serverUrl
        self.serverLabel = serverLabel
        self.serverDescription = serverDescription
        self.allowedTools = allowedTools
        self.headers = headers
        self.authorization = authorization
    }
}

private let xaiMcpServerArgsJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "additionalProperties": .bool(true)
])

public let xaiMcpServerArgsSchema = FlexibleSchema(
    Schema<XAIMCPServerArgs>(
        jsonSchemaResolver: { xaiMcpServerArgsJSONSchema },
        validator: { value in
            do {
                let json = try jsonValue(from: value)
                guard case .object(let dict) = json else {
                    let error = SchemaValidationIssuesError(
                        vendor: "xai",
                        issues: "mcp args must be an object"
                    )
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                guard let rawServerUrl = dict["serverUrl"],
                      case .string(let serverUrl) = rawServerUrl else {
                    let error = SchemaValidationIssuesError(
                        vendor: "xai",
                        issues: "serverUrl must be a string"
                    )
                    return .failure(error: TypeValidationError.wrap(value: dict["serverUrl"] ?? .null, cause: error))
                }

                func parseOptionalString(_ key: String) -> Result<String?, TypeValidationError> {
                    guard let raw = dict[key], raw != .null else { return .success(nil) }
                    guard case .string(let value) = raw else {
                        let error = SchemaValidationIssuesError(vendor: "xai", issues: "\(key) must be a string")
                        return .failure(TypeValidationError.wrap(value: raw, cause: error))
                    }
                    return .success(value)
                }

                func parseOptionalStringArray(_ key: String) -> Result<[String]?, TypeValidationError> {
                    guard let raw = dict[key], raw != .null else { return .success(nil) }
                    guard case .array(let values) = raw else {
                        let error = SchemaValidationIssuesError(vendor: "xai", issues: "\(key) must be an array of strings")
                        return .failure(TypeValidationError.wrap(value: raw, cause: error))
                    }
                    var strings: [String] = []
                    for item in values {
                        guard case .string(let value) = item else {
                            let error = SchemaValidationIssuesError(vendor: "xai", issues: "\(key) must be an array of strings")
                            return .failure(TypeValidationError.wrap(value: item, cause: error))
                        }
                        strings.append(value)
                    }
                    return .success(strings)
                }

                func parseOptionalStringRecord(_ key: String) -> Result<[String: String]?, TypeValidationError> {
                    guard let raw = dict[key], raw != .null else { return .success(nil) }
                    guard case .object(let value) = raw else {
                        let error = SchemaValidationIssuesError(vendor: "xai", issues: "\(key) must be an object")
                        return .failure(TypeValidationError.wrap(value: raw, cause: error))
                    }
                    var record: [String: String] = [:]
                    for (k, v) in value {
                        guard case .string(let str) = v else {
                            let error = SchemaValidationIssuesError(vendor: "xai", issues: "\(key) values must be strings")
                            return .failure(TypeValidationError.wrap(value: v, cause: error))
                        }
                        record[k] = str
                    }
                    return .success(record)
                }

                let serverLabel: String?
                switch parseOptionalString("serverLabel") {
                case .success(let value):
                    serverLabel = value
                case .failure(let error):
                    return .failure(error: error)
                }

                let serverDescription: String?
                switch parseOptionalString("serverDescription") {
                case .success(let value):
                    serverDescription = value
                case .failure(let error):
                    return .failure(error: error)
                }

                let allowedTools: [String]?
                switch parseOptionalStringArray("allowedTools") {
                case .success(let value):
                    allowedTools = value
                case .failure(let error):
                    return .failure(error: error)
                }

                let headers: [String: String]?
                switch parseOptionalStringRecord("headers") {
                case .success(let value):
                    headers = value
                case .failure(let error):
                    return .failure(error: error)
                }

                let authorization: String?
                switch parseOptionalString("authorization") {
                case .success(let value):
                    authorization = value
                case .failure(let error):
                    return .failure(error: error)
                }

                return .success(value: XAIMCPServerArgs(
                    serverUrl: serverUrl,
                    serverLabel: serverLabel,
                    serverDescription: serverDescription,
                    allowedTools: allowedTools,
                    headers: headers,
                    authorization: authorization
                ))
            } catch {
                return .failure(error: TypeValidationError.wrap(value: value, cause: error))
            }
        }
    )
)

private let emptyObjectJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "additionalProperties": .bool(false),
    "properties": .object([:])
])

private let mcpServerOutputJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "required": .array([.string("name"), .string("arguments"), .string("result")]),
    "additionalProperties": .bool(false),
    "properties": .object([
        "name": .object(["type": .string("string")]),
        "arguments": .object(["type": .string("string")]),
        "result": .bool(true)
    ])
])

public let xaiMcpServerToolFactory = createProviderToolFactoryWithOutputSchema(
    id: "xai.mcp",
    name: "mcp",
    inputSchema: FlexibleSchema(jsonSchema(emptyObjectJSONSchema)),
    outputSchema: FlexibleSchema(jsonSchema(mcpServerOutputJSONSchema))
) { (args: XAIMCPServerArgs) in
    var options = ProviderToolFactoryWithOutputSchemaOptions()

    var payload: [String: JSONValue] = [
        "serverUrl": .string(args.serverUrl)
    ]
    if let label = args.serverLabel {
        payload["serverLabel"] = .string(label)
    }
    if let description = args.serverDescription {
        payload["serverDescription"] = .string(description)
    }
    if let allowed = args.allowedTools {
        payload["allowedTools"] = .array(allowed.map(JSONValue.string))
    }
    if let headers = args.headers {
        payload["headers"] = .object(headers.mapValues(JSONValue.string))
    }
    if let authorization = args.authorization {
        payload["authorization"] = .string(authorization)
    }

    options.args = payload
    return options
}
