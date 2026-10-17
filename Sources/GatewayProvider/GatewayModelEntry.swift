import Foundation

public struct GatewayLanguageModelSpecification: Sendable, Decodable {
    public let specificationVersion = "v4"
    public let provider: String
    public let modelId: String

    public init(provider: String, modelId: String) {
        self.provider = provider
        self.modelId = modelId
    }

    private enum CodingKeys: String, CodingKey { case specificationVersion, provider, modelId }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .specificationVersion) == "v4" else {
            throw DecodingError.dataCorruptedError(
                forKey: .specificationVersion, in: container, debugDescription: "Expected v4 specification"
            )
        }
        provider = try container.decode(String.self, forKey: .provider)
        modelId = try container.decode(String.self, forKey: .modelId)
    }
}

public struct GatewayLanguageModelEntry: Sendable, Decodable {
    public struct Pricing: Sendable, Decodable {
        public let input: String
        public let output: String
        public let cachedInputTokens: String?
        public let cacheCreationInputTokens: String?

        private enum CodingKeys: String, CodingKey {
            case input, output, inputCacheRead, inputCacheWrite
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
            cachedInputTokens = try container.decodeIfPresent(String.self, forKey: .inputCacheRead).flatMap { $0.isEmpty ? nil : $0 }
            cacheCreationInputTokens = try container.decodeIfPresent(String.self, forKey: .inputCacheWrite).flatMap { $0.isEmpty ? nil : $0 }
        }
    }

    public let id: String
    public let name: String
    public let description: String?
    public let pricing: Pricing?
    public let specification: GatewayLanguageModelSpecification
    public let modelType: String?

    public init(
        id: String,
        name: String,
        description: String? = nil,
        pricing: Pricing? = nil,
        specification: GatewayLanguageModelSpecification,
        modelType: String? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.pricing = pricing
        self.specification = specification
        self.modelType = modelType
    }
}
