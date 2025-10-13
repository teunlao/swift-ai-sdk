import Foundation
import AISDKProvider

/**
 Request metadata for language model calls.

 Port of `@ai-sdk/ai/src/types/language-model-request-metadata.ts`.

 Contains optional HTTP body that was sent to the provider API.
 */
public struct LanguageModelRequestMetadata: Sendable, Equatable {
    /// Request HTTP body that was sent to the provider API.
    public let body: JSONValue?

    public init(body: JSONValue? = nil) {
        self.body = body
    }
}

// MARK: - Codable

extension LanguageModelRequestMetadata: Codable {
    enum CodingKeys: String, CodingKey {
        case body
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.body = try container.decodeIfPresent(JSONValue.self, forKey: .body)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(body, forKey: .body)
    }
}
