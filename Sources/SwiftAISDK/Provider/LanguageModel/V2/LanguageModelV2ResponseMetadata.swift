import Foundation

/**
 Optional response metadata for telemetry and debugging purposes.

 TypeScript equivalent:
 ```typescript
 export type LanguageModelV2ResponseMetadata = {
   id?: string;
   modelId?: string;
   timestamp?: Date;
 };
 ```
 */
public struct LanguageModelV2ResponseMetadata: Sendable, Equatable, Codable {
    /// Optional response ID
    public let id: String?

    /// Optional model ID used for the response
    public let modelId: String?

    /// Optional timestamp of the response
    public let timestamp: Date?

    public init(
        id: String? = nil,
        modelId: String? = nil,
        timestamp: Date? = nil
    ) {
        self.id = id
        self.modelId = modelId
        self.timestamp = timestamp
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case modelId
        case timestamp
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        modelId = try container.decodeIfPresent(String.self, forKey: .modelId)
        timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encodeIfPresent(modelId, forKey: .modelId)
        try container.encodeIfPresent(timestamp, forKey: .timestamp)
    }
}
