import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct GoogleFileSearchArgs: Sendable, Equatable {
    /// Fully-qualified File Search store resource names.
    public var fileSearchStoreNames: [String]

    /// Optional result limit for the number of chunks returned from File Search.
    public var topK: Int?

    /// Optional filter expression to restrict the files that can be retrieved.
    /// See https://google.aip.dev/160 for syntax.
    public var metadataFilter: String?

    /// Additional provider-specific parameters supported by Google.
    /// Upstream schema uses `.passthrough()`.
    public var extra: [String: JSONValue]

    public init(
        fileSearchStoreNames: [String],
        topK: Int? = nil,
        metadataFilter: String? = nil,
        extra: [String: JSONValue] = [:]
    ) {
        self.fileSearchStoreNames = fileSearchStoreNames
        self.topK = topK
        self.metadataFilter = metadataFilter
        self.extra = extra
    }
}

private let googleFileSearchInputSchema = FlexibleSchema(jsonSchema(.object([
    "type": .string("object"),
    "properties": .object([:]),
    "additionalProperties": .bool(false)
])))

public let googleFileSearchToolFactory = createProviderExecutedToolFactory(
    id: "google.file_search",
    name: "file_search",
    inputSchema: googleFileSearchInputSchema,
    outputSchema: FlexibleSchema(jsonSchema(.object([
        "type": .string("object"),
        "properties": .object([:]),
        "additionalProperties": .bool(false),
    ])))
) { (args: GoogleFileSearchArgs) in
    var options = ProviderExecutedToolFactoryOptions(args: args.extra)

    options.args["fileSearchStoreNames"] = .array(args.fileSearchStoreNames.map { .string($0) })

    if let topK = args.topK {
        options.args["topK"] = .number(Double(topK))
    }
    if let metadataFilter = args.metadataFilter {
        options.args["metadataFilter"] = .string(metadataFilter)
    }

    return options
}

@discardableResult
public func googleFileSearchTool(_ args: GoogleFileSearchArgs) -> Tool {
    googleFileSearchToolFactory(args)
}

