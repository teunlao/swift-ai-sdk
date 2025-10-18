import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct OpenAIFileSearchArgs: Sendable, Equatable {
    public struct RankingOptions: Sendable, Equatable {
        public let ranker: String?
        public let scoreThreshold: Double?

        public init(ranker: String? = nil, scoreThreshold: Double? = nil) {
            self.ranker = ranker
            self.scoreThreshold = scoreThreshold
        }
    }

    public let vectorStoreIds: [String]
    public let maxNumResults: Int?
    public let ranking: RankingOptions?
    public let filters: JSONValue?

    public init(
        vectorStoreIds: [String],
        maxNumResults: Int? = nil,
        ranking: RankingOptions? = nil,
        filters: JSONValue? = nil
    ) {
        self.vectorStoreIds = vectorStoreIds
        self.maxNumResults = maxNumResults
        self.ranking = ranking
        self.filters = filters
    }
}

private let comparisonFilterSchema: JSONValue = .object([
    "type": .string("object"),
    "required": .array([.string("key"), .string("type"), .string("value")]),
    "additionalProperties": .bool(false),
    "properties": .object([
        "key": .object(["type": .string("string")]),
        "type": .object([
            "type": .string("string"),
            "enum": .array([
                .string("eq"), .string("ne"), .string("gt"), .string("gte"), .string("lt"), .string("lte")
            ])
        ]),
        "value": .object([
            "type": .array([.string("string"), .string("number"), .string("boolean")])
        ])
    ])
])

private let compoundFilterSchema: JSONValue = .object([
    "type": .string("object"),
    "required": .array([.string("type"), .string("filters")]),
    "additionalProperties": .bool(false),
    "properties": .object([
        "type": .object([
            "type": .string("string"),
            "enum": .array([.string("and"), .string("or")])
        ]),
        "filters": .object([
            "type": .string("array"),
            "items": .object(["type": .array([.string("object")])])
        ])
    ])
])

public let openaiFileSearchArgsSchema = FlexibleSchema<OpenAIFileSearchArgs>(
    Schema(
        jsonSchemaResolver: {
            .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "required": .array([.string("vectorStoreIds")]),
                "properties": .object([
                    "vectorStoreIds": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")])
                    ]),
                    "maxNumResults": .object([
                        "type": .array([.string("number"), .string("null")])
                    ]),
                    "ranking": .object([
                        "type": .array([.string("object"), .string("null")]),
                        "properties": .object([
                            "ranker": .object(["type": .array([.string("string"), .string("null")])]),
                            "scoreThreshold": .object(["type": .array([.string("number"), .string("null")])])
                        ]),
                        "additionalProperties": .bool(false)
                    ]),
                    "filters": .bool(true)
                ])
            ])
        },
        validator: { value in
            do {
                let json = try jsonValue(from: value)
                guard case .object(let dict) = json else {
                    let error = SchemaValidationIssuesError(vendor: "openai", issues: "expected object")
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                guard case .array(let vectorIdsValue)? = dict["vectorStoreIds"] else {
                    let error = SchemaValidationIssuesError(vendor: "openai", issues: "vectorStoreIds must be an array")
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                let vectorStoreIds: [String] = try vectorIdsValue.map { element in
                    guard case .string(let id) = element else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "vectorStoreIds must contain strings")
                        throw TypeValidationError.wrap(value: element, cause: error)
                    }
                    return id
                }

                let maxNumResults: Int?
                if let maxValue = dict["maxNumResults"], maxValue != .null {
                    guard case .number(let number) = maxValue else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "maxNumResults must be a number")
                        return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                    }
                    maxNumResults = Int(number)
                } else {
                    maxNumResults = nil
                }

                var ranking: OpenAIFileSearchArgs.RankingOptions?
                if let rankingValue = dict["ranking"], rankingValue != .null {
                    guard case .object(let rankingObject) = rankingValue else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "ranking must be an object")
                        return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                    }
                    var ranker: String?
                    if let rankerValue = rankingObject["ranker"], rankerValue != .null {
                        guard case .string(let rankerString) = rankerValue else {
                            let error = SchemaValidationIssuesError(vendor: "openai", issues: "ranking.ranker must be a string")
                            return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                        }
                        ranker = rankerString
                    }
                    var scoreThreshold: Double?
                    if let scoreValue = rankingObject["scoreThreshold"], scoreValue != .null {
                        guard case .number(let number) = scoreValue else {
                            let error = SchemaValidationIssuesError(vendor: "openai", issues: "ranking.scoreThreshold must be a number")
                            return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                        }
                        scoreThreshold = number
                    }
                    ranking = OpenAIFileSearchArgs.RankingOptions(ranker: ranker, scoreThreshold: scoreThreshold)
                }

                let filters = dict["filters"]
                if let filters, filters != .null {
                    guard isValidFileSearchFilter(filters) else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "filters must be a comparison or compound filter")
                        return .failure(error: TypeValidationError.wrap(value: filters, cause: error))
                    }
                }

                let args = OpenAIFileSearchArgs(
                    vectorStoreIds: vectorStoreIds,
                    maxNumResults: maxNumResults,
                    ranking: ranking,
                    filters: dict["filters"]
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

private func isValidFileSearchFilter(_ value: JSONValue) -> Bool {
    guard case .object(let object) = value else { return false }

    if let typeValue = object["type"] {
        if case .string(let type) = typeValue {
            if type == "and" || type == "or" {
                guard let filtersValue = object["filters"], case .array(let filters) = filtersValue else {
                    return false
                }
                return filters.allSatisfy(isValidFileSearchFilter)
            }

            if ["eq", "ne", "gt", "gte", "lt", "lte"].contains(type) {
                guard let keyValue = object["key"], case .string = keyValue else {
                    return false
                }
                guard let comparisonValue = object["value"] else {
                    return false
                }
                switch comparisonValue {
                case .string, .number, .bool:
                    return true
                default:
                    return false
                }
            }
        }
    }

    return false
}

private let fileSearchInputJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "additionalProperties": .bool(false)
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
            "type": .array([.string("array"), .string("null")]),
            "items": .object([
                "type": .string("object"),
                "required": .array([
                    .string("attributes"), .string("fileId"), .string("filename"), .string("score"), .string("text")
                ]),
                "additionalProperties": .bool(false),
                "properties": .object([
                    "attributes": .object(["type": .string("object")]),
                    "fileId": .object(["type": .string("string")]),
                    "filename": .object(["type": .string("string")]),
                    "score": .object(["type": .string("number")]),
                    "text": .object(["type": .string("string")])
                ])
            ])
        ])
    ])
])

public let openaiFileSearchToolFactory = createProviderDefinedToolFactoryWithOutputSchema(
    id: "openai.file_search",
    name: "file_search",
    inputSchema: FlexibleSchema(jsonSchema(fileSearchInputJSONSchema)),
    outputSchema: FlexibleSchema(jsonSchema(fileSearchOutputJSONSchema))
) { (args: OpenAIFileSearchArgs) in
    var options = ProviderDefinedToolFactoryWithOutputSchemaOptions()
    options.args = encodeOpenAIFileSearchArgs(args)
    return options
}

private func encodeOpenAIFileSearchArgs(_ args: OpenAIFileSearchArgs) -> [String: JSONValue] {
    var payload: [String: JSONValue] = [
        "vectorStoreIds": .array(args.vectorStoreIds.map(JSONValue.string))
    ]

    if let max = args.maxNumResults {
        payload["maxNumResults"] = .number(Double(max))
    }

    if let ranking = args.ranking {
        var rankingPayload: [String: JSONValue] = [:]
        if let ranker = ranking.ranker {
            rankingPayload["ranker"] = .string(ranker)
        }
        if let score = ranking.scoreThreshold {
            rankingPayload["scoreThreshold"] = .number(score)
        }
        if !rankingPayload.isEmpty {
            payload["ranking"] = .object(rankingPayload)
        }
    }

    if let filters = args.filters {
        payload["filters"] = filters
    }

    return payload
}
