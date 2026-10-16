import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Request metadata for language model calls.

 Port of `@ai-sdk/ai/src/types/language-model-request-metadata.ts`.
 */
public struct LanguageModelRequestMetadata: Sendable, Equatable {
    /// The messages that were sent to the model, when retained (`include.requestMessages`).
    public let messages: [ModelMessage]?

    /// The HTTP body that was sent to the provider API, when retained (`include.requestBody`).
    public let body: JSONValue?

    public init(messages: [ModelMessage]? = nil, body: JSONValue? = nil) {
        self.messages = messages
        self.body = body
    }
}

// MARK: - Codable

extension LanguageModelRequestMetadata: Codable {
    enum CodingKeys: String, CodingKey {
        case messages
        case body
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.messages = try container.decodeIfPresent([ModelMessage].self, forKey: .messages)
        self.body = try container.decodeIfPresent(JSONValue.self, forKey: .body)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(messages, forKey: .messages)
        try container.encodeIfPresent(body, forKey: .body)
    }
}
