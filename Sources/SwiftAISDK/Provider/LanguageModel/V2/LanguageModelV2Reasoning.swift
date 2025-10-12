import Foundation

/**
 Reasoning content that the model has generated.

 TypeScript equivalent:
 ```typescript
 export type LanguageModelV2Reasoning = {
   type: 'reasoning';
   text: string;
   providerMetadata?: SharedV2ProviderMetadata;
 };
 ```
 */
public struct LanguageModelV2Reasoning: Sendable, Equatable, Codable {
    public let type: String = "reasoning"
    public let text: String
    public let providerMetadata: SharedV2ProviderMetadata?

    public init(text: String, providerMetadata: SharedV2ProviderMetadata? = nil) {
        self.text = text
        self.providerMetadata = providerMetadata
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case providerMetadata
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decode(String.self, forKey: .text)
        providerMetadata = try container.decodeIfPresent(SharedV2ProviderMetadata.self, forKey: .providerMetadata)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(text, forKey: .text)
        try container.encodeIfPresent(providerMetadata, forKey: .providerMetadata)
    }
}
