import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct GoogleVertexRAGStoreArgs: Sendable, Equatable {
    /// RagCorpus resource name, e.g. `projects/{project}/locations/{location}/ragCorpora/{rag_corpus}`.
    public var ragCorpus: String

    /// Optional number of top contexts to retrieve.
    public var topK: Double?

    public init(ragCorpus: String, topK: Double? = nil) {
        self.ragCorpus = ragCorpus
        self.topK = topK
    }
}

private let googleVertexRAGStoreInputSchema = FlexibleSchema(
    jsonSchema(
        .object([
            "type": .string("object"),
            "properties": .object([
                "ragCorpus": .object(["type": .string("string")]),
                "topK": .object(["type": .string("number")]),
            ]),
            "required": .array([.string("ragCorpus")]),
            "additionalProperties": .bool(false),
        ])
    )
)

public let googleVertexRAGStoreToolFactory = createProviderToolFactory(
    id: "google.vertex_rag_store",
    name: "vertex_rag_store",
    inputSchema: googleVertexRAGStoreInputSchema
) { (args: GoogleVertexRAGStoreArgs) in
    var options = ProviderToolFactoryOptions(args: [
        "ragCorpus": .string(args.ragCorpus),
    ])
    if let topK = args.topK {
        options.args["topK"] = .number(topK)
    }
    return options
}

@discardableResult
public func googleVertexRAGStoreTool(_ args: GoogleVertexRAGStoreArgs) -> Tool {
    googleVertexRAGStoreToolFactory(args)
}

