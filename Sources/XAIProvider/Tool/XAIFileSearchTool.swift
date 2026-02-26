import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct XAIFileSearchArgs: Sendable, Equatable {
    public var vectorStoreIds: [String]
    public var maxNumResults: Int?

    public init(vectorStoreIds: [String], maxNumResults: Int? = nil) {
        self.vectorStoreIds = vectorStoreIds
        self.maxNumResults = maxNumResults
    }
}

private let xaiFileSearchArgsJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "additionalProperties": .bool(true)
])

public let xaiFileSearchArgsSchema = FlexibleSchema(
    Schema<XAIFileSearchArgs>(
        jsonSchemaResolver: { xaiFileSearchArgsJSONSchema },
        validator: { value in
            do {
                let json = try jsonValue(from: value)
                guard case .object(let dict) = json else {
                    let error = SchemaValidationIssuesError(
                        vendor: "xai",
                        issues: "fileSearch args must be an object"
                    )
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                guard let rawVectorStoreIds = dict["vectorStoreIds"],
                      case .array(let values) = rawVectorStoreIds else {
                    let error = SchemaValidationIssuesError(
                        vendor: "xai",
                        issues: "vectorStoreIds must be an array of strings"
                    )
                    return .failure(error: TypeValidationError.wrap(value: dict["vectorStoreIds"] ?? .null, cause: error))
                }

                var vectorStoreIds: [String] = []
                for item in values {
                    guard case .string(let value) = item else {
                        let error = SchemaValidationIssuesError(
                            vendor: "xai",
                            issues: "vectorStoreIds must be an array of strings"
                        )
                        return .failure(error: TypeValidationError.wrap(value: item, cause: error))
                    }
                    vectorStoreIds.append(value)
                }

                var maxNumResults: Int? = nil
                if let rawMax = dict["maxNumResults"], rawMax != .null {
                    guard case .number(let value) = rawMax else {
                        let error = SchemaValidationIssuesError(
                            vendor: "xai",
                            issues: "maxNumResults must be a number"
                        )
                        return .failure(error: TypeValidationError.wrap(value: rawMax, cause: error))
                    }
                    maxNumResults = Int(value)
                }

                return .success(value: XAIFileSearchArgs(
                    vectorStoreIds: vectorStoreIds,
                    maxNumResults: maxNumResults
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

private let fileSearchOutputJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "required": .array([.string("queries"), .string("results")]),
    "additionalProperties": .bool(false),
    "properties": .object([
        "queries": .object([
            "type": .string("array"),
            "items": .object(["type": .string("string")])
        ]),
        "results": .object([
            "anyOf": .array([
                .object(["type": .string("null")]),
                .object([
                    "type": .string("array"),
                    "items": .object([
                        "type": .string("object"),
                        "required": .array([.string("fileId"), .string("filename"), .string("score"), .string("text")]),
                        "additionalProperties": .bool(false),
                        "properties": .object([
                            "fileId": .object(["type": .string("string")]),
                            "filename": .object(["type": .string("string")]),
                            "score": .object(["type": .string("number")]),
                            "text": .object(["type": .string("string")])
                        ])
                    ])
                ])
            ])
        ])
    ])
])

public let xaiFileSearchToolFactory = createProviderToolFactoryWithOutputSchema(
    id: "xai.file_search",
    name: "file_search",
    inputSchema: FlexibleSchema(jsonSchema(emptyObjectJSONSchema)),
    outputSchema: FlexibleSchema(jsonSchema(fileSearchOutputJSONSchema))
) { (args: XAIFileSearchArgs) in
    var options = ProviderToolFactoryWithOutputSchemaOptions()

    var payload: [String: JSONValue] = [
        "vectorStoreIds": .array(args.vectorStoreIds.map(JSONValue.string))
    ]
    if let max = args.maxNumResults {
        payload["maxNumResults"] = .number(Double(max))
    }

    options.args = payload
    return options
}

