import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/gateway/src/gateway-model-entry.ts
// Upstream commit: 73d5c5920
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
            // Decoded via JSONDecoder.keyDecodingStrategy = .convertFromSnakeCase upstream parity.
            case inputCacheRead
            case inputCacheWrite
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

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case pricing
        case specification
        case modelType
    }

    public init(
        id: String,
        name: String,
        description: String? = nil,
        pricing: Pricing? = nil,
        specification: Specification,
        modelType: String? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.pricing = pricing
        self.specification = specification
        self.modelType = modelType
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        pricing = try container.decodeIfPresent(Pricing.self, forKey: .pricing)
        specification = try container.decode(Specification.self, forKey: .specification)

        if let rawModelType = try container.decodeIfPresent(String.self, forKey: .modelType) {
            switch rawModelType {
            case "language", "embedding", "image", "video":
                modelType = rawModelType
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .modelType,
                    in: container,
                    debugDescription: "Invalid modelType value: \(rawModelType)"
                )
            }
        } else {
            modelType = nil
        }
    }
}
