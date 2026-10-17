import Foundation
import AISDKProviderUtils

public struct CohereRerankingModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.init(rawValue: value) }
    public static let rerankV35: Self = "rerank-v3.5"
    public static let rerankEnglishV30: Self = "rerank-english-v3.0"
    public static let rerankMultilingualV30: Self = "rerank-multilingual-v3.0"
}

public struct CohereRerankingModelOptions: Sendable, Equatable, Codable {
    public var maxTokensPerDoc: Double?
    public var priority: Double?

    public init(maxTokensPerDoc: Double? = nil, priority: Double? = nil) {
        self.maxTokensPerDoc = maxTokensPerDoc
        self.priority = priority
    }
    private enum CodingKeys: String, CodingKey { case maxTokensPerDoc, priority }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            maxTokensPerDoc: container.contains(.maxTokensPerDoc) ? container.decode(Double.self, forKey: .maxTokensPerDoc) : nil,
            priority: container.contains(.priority) ? container.decode(Double.self, forKey: .priority) : nil
        )
    }
}

let cohereRerankingModelOptionsSchema = FlexibleSchema(
    Schema<CohereRerankingModelOptions>.codable(CohereRerankingModelOptions.self, jsonSchema: ["type": "object"])
)
