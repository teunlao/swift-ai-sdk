import AISDKProvider
import AISDKProviderUtils

public struct OpenAIFileSearchArgs: Codable, Sendable, Equatable {
    public struct RankingOptions: Codable, Sendable, Equatable {
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

    public init(vectorStoreIds: [String], maxNumResults: Int? = nil, ranking: RankingOptions? = nil, filters: JSONValue? = nil) {
        self.vectorStoreIds = vectorStoreIds
        self.maxNumResults = maxNumResults
        self.ranking = ranking
        self.filters = filters
    }
}

private let fileSearchStrings: JSONValue = .object(["type": .string("array"), "items": .object(["type": .string("string")])])
private let fileSearchFilterSchema: JSONValue = .object([
    "anyOf": .array([
        .object([
            "type": .string("object"), "additionalProperties": .bool(false),
            "required": .array([.string("key"), .string("type"), .string("value")]),
            "properties": .object([
                "key": .object(["type": .string("string")]),
                "type": .object(["enum": .array(["eq", "ne", "gt", "gte", "lt", "lte", "in", "nin"].map(JSONValue.string))]),
                "value": .object(["anyOf": .array([
                    .object(["type": .string("string")]), .object(["type": .string("number")]),
                    .object(["type": .string("boolean")]), fileSearchStrings
                ])])
            ])
        ]),
        .object([
            "type": .string("object"), "additionalProperties": .bool(false),
            "required": .array([.string("type"), .string("filters")]),
            "properties": .object([
                "type": .object(["enum": .array([.string("and"), .string("or")])]),
                "filters": .object(["type": .string("array"), "items": .object(["$ref": .string("#/$defs/filter")])])
            ])
        ])
    ])
])
private let fileSearchArgsJSONSchema: JSONValue = .object([
    "type": .string("object"), "additionalProperties": .bool(false),
    "required": .array([.string("vectorStoreIds")]),
    "$defs": .object(["filter": fileSearchFilterSchema]),
    "properties": .object([
        "vectorStoreIds": fileSearchStrings,
        "maxNumResults": .object(["type": .string("integer")]),
        "ranking": .object([
            "type": .string("object"), "additionalProperties": .bool(false),
            "properties": .object([
                "ranker": .object(["type": .string("string")]),
                "scoreThreshold": .object(["type": .string("number")])
            ])
        ]),
        "filters": .object(["$ref": .string("#/$defs/filter")])
    ])
])

public let openaiFileSearchArgsSchema = openAIToolSchema(OpenAIFileSearchArgs.self, fileSearchArgsJSONSchema)

private let fileSearchInputJSONSchema: JSONValue = .object(["type": .string("object"), "additionalProperties": .bool(false)])
private let fileSearchOutputJSONSchema: JSONValue = .object([
    "type": .string("object"), "required": .array([.string("queries"), .string("results")]), "additionalProperties": .bool(false),
    "properties": .object([
        "queries": fileSearchStrings,
        "results": .object([
            "type": .array([.string("array"), .string("null")]),
            "items": .object([
                "type": .string("object"), "additionalProperties": .bool(false),
                "required": .array([.string("attributes"), .string("fileId"), .string("filename"), .string("score"), .string("text")]),
                "properties": .object([
                    "attributes": .object(["type": .string("object")]),
                    "fileId": .object(["type": .string("string")]), "filename": .object(["type": .string("string")]),
                    "score": .object(["type": .string("number")]), "text": .object(["type": .string("string")])
                ])
            ])
        ])
    ])
])
public let openaiFileSearchOutputSchema = openAIToolSchema(fileSearchOutputJSONSchema)
public let openaiFileSearchToolFactory = createProviderExecutedToolFactory(
    id: "openai.file_search", name: "file_search",
    inputSchema: openAIToolSchema(fileSearchInputJSONSchema), outputSchema: openaiFileSearchOutputSchema
) { (args: OpenAIFileSearchArgs) in
    var options = ProviderExecutedToolFactoryOptions()
    options.args["vectorStoreIds"] = .array(args.vectorStoreIds.map(JSONValue.string))
    if let value = args.maxNumResults { options.args["maxNumResults"] = .number(Double(value)) }
    if let ranking = args.ranking {
        var payload: [String: JSONValue] = [:]
        if let value = ranking.ranker { payload["ranker"] = .string(value) }
        if let value = ranking.scoreThreshold { payload["scoreThreshold"] = .number(value) }
        options.args["ranking"] = .object(payload)
    }
    options.args["filters"] = args.filters
    return options
}
