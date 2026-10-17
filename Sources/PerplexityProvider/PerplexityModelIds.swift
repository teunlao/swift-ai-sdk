public enum PerplexityAgentPreset: String, Sendable, Codable, CaseIterable {
    case fast, low, medium, high, xhigh
}

public struct PerplexityLanguageModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, Codable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.init(rawValue: value) }

    public static let fast = Self(rawValue: PerplexityAgentPreset.fast.rawValue)
    public static let low = Self(rawValue: PerplexityAgentPreset.low.rawValue)
    public static let medium = Self(rawValue: PerplexityAgentPreset.medium.rawValue)
    public static let high = Self(rawValue: PerplexityAgentPreset.high.rawValue)
    public static let xhigh = Self(rawValue: PerplexityAgentPreset.xhigh.rawValue)
    public static let perplexitySonar: Self = "perplexity/sonar"
}

public struct PerplexityEmbeddingModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, Codable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.init(rawValue: value) }

    public static let pplxEmbedV106b: Self = "pplx-embed-v1-0.6b"
    public static let pplxEmbedV14b: Self = "pplx-embed-v1-4b"
}
