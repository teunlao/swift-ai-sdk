import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct XAIXSearchArgs: Sendable, Equatable {
    public var allowedXHandles: [String]?
    public var excludedXHandles: [String]?
    public var fromDate: String?
    public var toDate: String?
    public var enableImageUnderstanding: Bool?
    public var enableVideoUnderstanding: Bool?

    public init(
        allowedXHandles: [String]? = nil,
        excludedXHandles: [String]? = nil,
        fromDate: String? = nil,
        toDate: String? = nil,
        enableImageUnderstanding: Bool? = nil,
        enableVideoUnderstanding: Bool? = nil
    ) {
        self.allowedXHandles = allowedXHandles
        self.excludedXHandles = excludedXHandles
        self.fromDate = fromDate
        self.toDate = toDate
        self.enableImageUnderstanding = enableImageUnderstanding
        self.enableVideoUnderstanding = enableVideoUnderstanding
    }
}

private let xaiXSearchArgsJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "additionalProperties": .bool(true)
])

public let xaiXSearchArgsSchema = FlexibleSchema(
    Schema<XAIXSearchArgs>(
        jsonSchemaResolver: { xaiXSearchArgsJSONSchema },
        validator: { value in
            do {
                let json = try jsonValue(from: value)
                guard case .object(let dict) = json else {
                    let error = SchemaValidationIssuesError(
                        vendor: "xai",
                        issues: "xSearch args must be an object"
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

                let allowedXHandles: [String]?
                switch parseStringArray("allowedXHandles", max: 10) {
                case .success(let value):
                    allowedXHandles = value
                case .failure(let error):
                    return .failure(error: error)
                }

                let excludedXHandles: [String]?
                switch parseStringArray("excludedXHandles", max: 10) {
                case .success(let value):
                    excludedXHandles = value
                case .failure(let error):
                    return .failure(error: error)
                }

                func parseOptionalString(_ key: String) -> Result<String?, TypeValidationError> {
                    guard let raw = dict[key], raw != .null else { return .success(nil) }
                    guard case .string(let value) = raw else {
                        let error = SchemaValidationIssuesError(vendor: "xai", issues: "\(key) must be a string")
                        return .failure(TypeValidationError.wrap(value: raw, cause: error))
                    }
                    return .success(value)
                }

                let fromDate: String?
                switch parseOptionalString("fromDate") {
                case .success(let value):
                    fromDate = value
                case .failure(let error):
                    return .failure(error: error)
                }

                let toDate: String?
                switch parseOptionalString("toDate") {
                case .success(let value):
                    toDate = value
                case .failure(let error):
                    return .failure(error: error)
                }

                func parseOptionalBool(_ key: String) -> Result<Bool?, TypeValidationError> {
                    guard let raw = dict[key], raw != .null else { return .success(nil) }
                    guard case .bool(let value) = raw else {
                        let error = SchemaValidationIssuesError(vendor: "xai", issues: "\(key) must be a boolean")
                        return .failure(TypeValidationError.wrap(value: raw, cause: error))
                    }
                    return .success(value)
                }

                let enableImageUnderstanding: Bool?
                switch parseOptionalBool("enableImageUnderstanding") {
                case .success(let value):
                    enableImageUnderstanding = value
                case .failure(let error):
                    return .failure(error: error)
                }

                let enableVideoUnderstanding: Bool?
                switch parseOptionalBool("enableVideoUnderstanding") {
                case .success(let value):
                    enableVideoUnderstanding = value
                case .failure(let error):
                    return .failure(error: error)
                }

                return .success(value: XAIXSearchArgs(
                    allowedXHandles: allowedXHandles,
                    excludedXHandles: excludedXHandles,
                    fromDate: fromDate,
                    toDate: toDate,
                    enableImageUnderstanding: enableImageUnderstanding,
                    enableVideoUnderstanding: enableVideoUnderstanding
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

private let xSearchOutputJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "required": .array([.string("query"), .string("posts")]),
    "additionalProperties": .bool(false),
    "properties": .object([
        "query": .object(["type": .string("string")]),
        "posts": .object([
            "type": .string("array"),
            "items": .object([
                "type": .string("object"),
                "required": .array([.string("author"), .string("text"), .string("url"), .string("likes")]),
                "additionalProperties": .bool(false),
                "properties": .object([
                    "author": .object(["type": .string("string")]),
                    "text": .object(["type": .string("string")]),
                    "url": .object(["type": .string("string")]),
                    "likes": .object(["type": .string("number")])
                ])
            ])
        ])
    ])
])

public let xaiXSearchToolFactory = createProviderToolFactoryWithOutputSchema(
    id: "xai.x_search",
    name: "x_search",
    inputSchema: FlexibleSchema(jsonSchema(emptyObjectJSONSchema)),
    outputSchema: FlexibleSchema(jsonSchema(xSearchOutputJSONSchema))
) { (args: XAIXSearchArgs) in
    var options = ProviderToolFactoryWithOutputSchemaOptions()

    var payload: [String: JSONValue] = [:]
    if let allowed = args.allowedXHandles {
        payload["allowedXHandles"] = .array(allowed.map(JSONValue.string))
    }
    if let excluded = args.excludedXHandles {
        payload["excludedXHandles"] = .array(excluded.map(JSONValue.string))
    }
    if let fromDate = args.fromDate {
        payload["fromDate"] = .string(fromDate)
    }
    if let toDate = args.toDate {
        payload["toDate"] = .string(toDate)
    }
    if let enable = args.enableImageUnderstanding {
        payload["enableImageUnderstanding"] = .bool(enable)
    }
    if let enable = args.enableVideoUnderstanding {
        payload["enableVideoUnderstanding"] = .bool(enable)
    }

    options.args = payload
    return options
}

