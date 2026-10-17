import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct CohereEmbeddingModelOptions: Sendable, Equatable, Codable {
    public enum EmbeddingType: String, Sendable, Codable { case float, int8, uint8, binary, ubinary }
    public enum InputType: String, Sendable, Codable {
        case searchDocument = "search_document"
        case searchQuery = "search_query"
        case classification, clustering
    }
    public enum Truncate: String, Sendable, Codable { case none = "NONE", start = "START", end = "END" }
    public var embeddingType: EmbeddingType?
    public var inputType: InputType?
    public var truncate: Truncate?
    public var outputDimension: Int?

    public init(embeddingType: EmbeddingType? = nil, inputType: InputType? = nil, truncate: Truncate? = nil, outputDimension: Int? = nil) {
        self.embeddingType = embeddingType
        self.inputType = inputType
        self.truncate = truncate
        self.outputDimension = outputDimension
    }

    private enum CodingKeys: String, CodingKey { case embeddingType, inputType, truncate, outputDimension }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            embeddingType: container.contains(.embeddingType) ? container.decode(EmbeddingType.self, forKey: .embeddingType) : nil,
            inputType: container.contains(.inputType) ? container.decode(InputType.self, forKey: .inputType) : nil,
            truncate: container.contains(.truncate) ? container.decode(Truncate.self, forKey: .truncate) : nil,
            outputDimension: container.contains(.outputDimension) ? container.decode(Int.self, forKey: .outputDimension) : nil
        )
        if let outputDimension, ![256, 512, 768, 1024, 1536, 2048].contains(outputDimension) {
            throw DecodingError.dataCorruptedError(forKey: .outputDimension, in: container, debugDescription: "Unsupported output dimension")
        }
    }
}

let cohereEmbeddingModelOptions = FlexibleSchema(
    Schema<CohereEmbeddingModelOptions>.codable(CohereEmbeddingModelOptions.self, jsonSchema: ["type": "object"])
)
