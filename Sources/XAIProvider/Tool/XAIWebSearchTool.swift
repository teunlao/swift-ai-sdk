import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct XAIWebSearchArgs: Sendable, Equatable {
    public var allowedDomains: [String]?
    public var excludedDomains: [String]?
    public var enableImageUnderstanding: Bool?
    public var enableImageSearch: Bool?

    public init(
        allowedDomains: [String]? = nil,
        excludedDomains: [String]? = nil,
        enableImageUnderstanding: Bool? = nil,
        enableImageSearch: Bool? = nil
    ) {
        self.allowedDomains = allowedDomains
        self.excludedDomains = excludedDomains
        self.enableImageUnderstanding = enableImageUnderstanding
        self.enableImageSearch = enableImageSearch
    }
}

private let xaiWebSearchArgsJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "additionalProperties": .bool(true)
])

public let xaiWebSearchArgsSchema = FlexibleSchema(
    Schema<XAIWebSearchArgs>(
        jsonSchemaResolver: { xaiWebSearchArgsJSONSchema },
        validator: { value in
            do {
                let json = try jsonValue(from: value)
                guard case .object(let dict) = json else {
                    let error = SchemaValidationIssuesError(
                        vendor: "xai",
                        issues: "webSearch args must be an object"
                    )
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                func parseStringArray(_ key: String, max: Int) -> Result<[String]?, TypeValidationError> {
                    guard let raw = dict[key], raw != .null else { return .success(nil) }
                    guard case .array(let values) = raw else {
                        let error = SchemaValidationIssuesError(vendor: "xai", issues: "\(key) must be an array of strings")
                        return .failure(TypeValidationError.wrap(value: raw, cause: error))
                    }
                    var strings: [String] = []
                    for item in values {
                        guard case .string(let str) = item else {
                            let error = SchemaValidationIssuesError(vendor: "xai", issues: "\(key) must be an array of strings")
                            return .failure(TypeValidationError.wrap(value: item, cause: error))
                        }
                        strings.append(str)
                    }
                    if strings.count > max {
                        let error = SchemaValidationIssuesError(vendor: "xai", issues: "\(key) must have at most \(max) entries")
                        return .failure(TypeValidationError.wrap(value: raw, cause: error))
                    }
                    return .success(strings)
                }

                let allowed: [String]?
                switch parseStringArray("allowedDomains", max: 5) {
                case .success(let value):
                    allowed = value
                case .failure(let error):
                    return .failure(error: error)
                }

                let excluded: [String]?
                switch parseStringArray("excludedDomains", max: 5) {
                case .success(let value):
                    excluded = value
                case .failure(let error):
                    return .failure(error: error)
                }

                var enableImageUnderstanding: Bool? = nil
                if let rawEnable = dict["enableImageUnderstanding"], rawEnable != .null {
                    guard case .bool(let bool) = rawEnable else {
                        let error = SchemaValidationIssuesError(vendor: "xai", issues: "enableImageUnderstanding must be a boolean")
                        return .failure(error: TypeValidationError.wrap(value: rawEnable, cause: error))
                    }
                    enableImageUnderstanding = bool
                }

                var enableImageSearch: Bool?
                if let raw = dict["enableImageSearch"] {
                    guard case .bool(let value) = raw else { throw InvalidArgumentError(argument: "enableImageSearch", message: "Expected a boolean") }
                    enableImageSearch = value
                }
                return .success(value: XAIWebSearchArgs(
                    allowedDomains: allowed,
                    excludedDomains: excluded,
                    enableImageUnderstanding: enableImageUnderstanding,
                    enableImageSearch: enableImageSearch
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

private let webSearchOutputJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "properties": .object([
        "action": .object(["oneOf": .array([
            .object(["type": .string("object"), "required": .array([.string("type")]), "properties": .object([
                "type": .object(["const": .string("search")]), "query": .object(["type": .string("string")]),
                "queries": .object(["type": .string("array"), "items": .object(["type": .string("string")])])
            ])]),
            .object(["type": .string("object"), "required": .array([.string("type")]), "properties": .object([
                "type": .object(["const": .string("openPage")]), "url": .object(["type": .array([.string("string"), .string("null")])])
            ])]),
            .object(["type": .string("object"), "required": .array([.string("type")]), "properties": .object([
                "type": .object(["const": .string("findInPage")]), "url": .object(["type": .array([.string("string"), .string("null")])]),
                "pattern": .object(["type": .array([.string("string"), .string("null")])])
            ])])
        ])]),
        "sources": .object(["type": .string("array"), "items": .object([
            "type": .string("object"), "required": .array([.string("type"), .string("url")]),
            "properties": .object(["type": .object(["const": .string("url")]), "url": .object(["type": .string("string")])])
        ])])
    ])
])

public let xaiWebSearchToolFactory = createProviderExecutedToolFactory(
    id: "xai.web_search",
    name: "web_search",
    inputSchema: FlexibleSchema(jsonSchema(emptyObjectJSONSchema)),
    outputSchema: FlexibleSchema(jsonSchema(webSearchOutputJSONSchema))
) { (args: XAIWebSearchArgs) in
    var options = ProviderExecutedToolFactoryOptions()

    var payload: [String: JSONValue] = [:]
    if let allowed = args.allowedDomains {
        payload["allowedDomains"] = .array(allowed.map(JSONValue.string))
    }
    if let excluded = args.excludedDomains {
        payload["excludedDomains"] = .array(excluded.map(JSONValue.string))
    }
    if let enable = args.enableImageUnderstanding {
        payload["enableImageUnderstanding"] = .bool(enable)
    }

    if let enable = args.enableImageSearch { payload["enableImageSearch"] = .bool(enable) }
    options.args = payload
    return options
}
