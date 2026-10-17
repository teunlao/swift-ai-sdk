import AISDKProviderUtils

public struct PerplexityEmbeddingModelOptions: Codable, Sendable, Equatable {
    public enum EncodingFormat: String, Codable, Sendable {
        case base64Int8 = "base64_int8"
        case base64Binary = "base64_binary"
    }
    public var dimensions: Int?
    public var encodingFormat: EncodingFormat?

    public init(dimensions: Int? = nil, encodingFormat: EncodingFormat? = nil) {
        self.dimensions = dimensions
        self.encodingFormat = encodingFormat
    }
    private enum CodingKeys: String, CodingKey { case dimensions, encodingFormat }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            dimensions: container.contains(.dimensions) ? container.decode(Int.self, forKey: .dimensions) : nil,
            encodingFormat: container.contains(.encodingFormat) ? container.decode(EncodingFormat.self, forKey: .encodingFormat) : nil
        )
        if let dimensions, dimensions <= 0 || dimensions > 9_007_199_254_740_991 {
            throw DecodingError.dataCorruptedError(forKey: .dimensions, in: container, debugDescription: "Expected a positive safe integer")
        }
    }
}

let perplexityEmbeddingModelOptions = FlexibleSchema(
    Schema<PerplexityEmbeddingModelOptions>.codable(PerplexityEmbeddingModelOptions.self, jsonSchema: ["type": "object"])
)
