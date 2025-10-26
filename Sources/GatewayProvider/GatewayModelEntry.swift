import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/gateway/src/gateway-model-entry.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public struct GatewayLanguageModelEntry: Sendable, Decodable {
    public struct Pricing: Sendable, Decodable {
        public let input: String
        public let output: String
        public let cachedInputTokens: String?
        public let cacheCreationInputTokens: String?

        private enum CodingKeys: String, CodingKey {
            case input
            case output
            case inputCacheRead = "input_cache_read"
            case inputCacheWrite = "input_cache_write"
        }

        public init(input: String, output: String, cachedInputTokens: String? = nil, cacheCreationInputTokens: String? = nil) {
            self.input = input
            self.output = output
            self.cachedInputTokens = cachedInputTokens
            self.cacheCreationInputTokens = cacheCreationInputTokens
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            input = try container.decode(String.self, forKey: .input)
            output = try container.decode(String.self, forKey: .output)
            cachedInputTokens = try container.decodeIfPresent(String.self, forKey: .inputCacheRead)
            cacheCreationInputTokens = try container.decodeIfPresent(String.self, forKey: .inputCacheWrite)
        }
    }

    public struct Specification: Sendable, Decodable {
        public let specificationVersion: String
        public let provider: String
        public let modelId: String
    }

    public let id: String
    public let name: String
    public let description: String?
    public let pricing: Pricing?
    public let specification: Specification
    public let modelType: String?
}
