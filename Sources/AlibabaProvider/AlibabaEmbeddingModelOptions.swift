import Foundation
import AISDKProviderUtils

public struct AlibabaEmbeddingModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, Codable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.init(rawValue: value) }
    public static let textEmbeddingV4: Self = "text-embedding-v4"
    public static let textEmbeddingV3: Self = "text-embedding-v3"
}
public struct AlibabaEmbeddingModelOptions: Codable, Sendable, Equatable {
    public enum TextType: String, Codable, Sendable { case query, document }
    public enum OutputType: String, Codable, Sendable { case dense, sparse; case denseAndSparse = "dense&sparse" }
    public var textType: TextType?
    public var dimension: Double?
    public var outputType: OutputType?
    public init(textType: TextType? = nil, dimension: Double? = nil, outputType: OutputType? = nil) {
        self.textType = textType; self.dimension = dimension; self.outputType = outputType
    }
    private enum Keys: String, CodingKey { case textType, dimension, outputType }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: Keys.self)
        try self.init(textType: values.contains(.textType) ? values.decode(TextType.self, forKey: .textType) : nil,
                      dimension: values.contains(.dimension) ? values.decode(Double.self, forKey: .dimension) : nil,
                      outputType: values.contains(.outputType) ? values.decode(OutputType.self, forKey: .outputType) : nil)
    }
}
let alibabaEmbeddingModelOptions = FlexibleSchema(Schema<AlibabaEmbeddingModelOptions>.codable(AlibabaEmbeddingModelOptions.self, jsonSchema: ["type": "object"]))
