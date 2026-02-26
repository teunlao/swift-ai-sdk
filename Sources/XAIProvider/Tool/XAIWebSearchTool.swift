import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct XAIWebSearchArgs: Sendable, Equatable {
    public var allowedDomains: [String]?
    public var excludedDomains: [String]?
    public var enableImageUnderstanding: Bool?

    public init(
        allowedDomains: [String]? = nil,
        excludedDomains: [String]? = nil,
        enableImageUnderstanding: Bool? = nil
    ) {
        self.allowedDomains = allowedDomains
        self.excludedDomains = excludedDomains
        self.enableImageUnderstanding = enableImageUnderstanding
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

                return .success(value: XAIWebSearchArgs(
                    allowedDomains: allowed,
                    excludedDomains: excluded,
                    enableImageUnderstanding: enableImageUnderstanding
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
    "required": .array([.string("query"), .string("sources")]),
    "additionalProperties": .bool(false),
    "properties": .object([
        "query": .object(["type": .string("string")]),
        "sources": .object([
            "type": .string("array"),
            "items": .object([
                "type": .string("object"),
                "required": .array([.string("title"), .string("url"), .string("snippet")]),
                "additionalProperties": .bool(false),
                "properties": .object([
                    "title": .object(["type": .string("string")]),
                    "url": .object(["type": .string("string")]),
                    "snippet": .object(["type": .string("string")])
                ])
            ])
        ])
    ])
])

public let xaiWebSearchToolFactory = createProviderToolFactoryWithOutputSchema(
    id: "xai.web_search",
    name: "web_search",
    inputSchema: FlexibleSchema(jsonSchema(emptyObjectJSONSchema)),
    outputSchema: FlexibleSchema(jsonSchema(webSearchOutputJSONSchema))
) { (args: XAIWebSearchArgs) in
    var options = ProviderToolFactoryWithOutputSchemaOptions()

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

    options.args = payload
    return options
}
