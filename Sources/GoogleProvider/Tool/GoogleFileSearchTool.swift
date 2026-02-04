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

private let googleFileSearchInputSchema = FlexibleSchema(
    jsonSchema(
        .object([
            "type": .string("object"),
            "properties": .object([
                "fileSearchStoreNames": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string")]),
                    "description": .string(
                        "The names of the file_search_stores to retrieve from. Example: `fileSearchStores/my-file-search-store-123`"
                    ),
                ]),
                "topK": .object([
                    "type": .string("integer"),
                    "minimum": .number(1),
                    "description": .string("The number of file search retrieval chunks to retrieve."),
                ]),
                "metadataFilter": .object([
                    "type": .string("string"),
                    "description": .string(
                        "Metadata filter to apply to the file search retrieval documents. See https://google.aip.dev/160 for the syntax of the filter expression."
                    ),
                ]),
            ]),
            "required": .array([.string("fileSearchStoreNames")]),
            "additionalProperties": .bool(true),
        ])
    )
)

public let googleFileSearchToolFactory = createProviderToolFactory(
    id: "google.file_search",
    name: "file_search",
    inputSchema: googleFileSearchInputSchema
) { (args: GoogleFileSearchArgs) in
    var options = ProviderToolFactoryOptions(args: args.extra)

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

