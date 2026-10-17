public struct MistralChatModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, Codable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.init(rawValue: value) }

    public static let codestral2508: Self = "codestral-2508"
    public static let codestralLatest: Self = "codestral-latest"
    public static let glm52: Self = "glm-5-2"
    public static let labsLeanstral15: Self = "labs-leanstral-1-5"
    public static let labsLeanstral151: Self = "labs-leanstral-1-5-1"
    public static let magistralMediumLatest: Self = "magistral-medium-latest"
    public static let magistralSmallLatest: Self = "magistral-small-latest"
    public static let ministral14b2512: Self = "ministral-14b-2512"
    public static let ministral14bLatest: Self = "ministral-14b-latest"
    public static let ministral3b2512: Self = "ministral-3b-2512"
    public static let ministral3bLatest: Self = "ministral-3b-latest"
    public static let ministral8b2512: Self = "ministral-8b-2512"
    public static let ministral8bLatest: Self = "ministral-8b-latest"
    public static let mistralCodeFimLatest: Self = "mistral-code-fim-latest"
    public static let mistralCodeLatest: Self = "mistral-code-latest"
    public static let mistralLarge4: Self = "mistral-large-4"
    public static let mistralLarge40: Self = "mistral-large-4-0"
    public static let mistralLargeLatest: Self = "mistral-large-latest"
    public static let mistralLarge2512: Self = "mistral-large-2512"
    public static let mistralMedium: Self = "mistral-medium"
    public static let mistralMediumLatest: Self = "mistral-medium-latest"
    public static let mistralMedium2604: Self = "mistral-medium-2604"
    public static let mistralMedium3: Self = "mistral-medium-3"
    public static let mistralMedium35: Self = "mistral-medium-3-5"
    public static let mistralMedium3Dot5: Self = "mistral-medium-3.5"
    public static let mistralSmall2603: Self = "mistral-small-2603"
    public static let mistralSmallLatest: Self = "mistral-small-latest"
    public static let mistralVibeCliFast: Self = "mistral-vibe-cli-fast"
    public static let mistralVibeCliLatest: Self = "mistral-vibe-cli-latest"
    public static let mistralVibeCliWithTools: Self = "mistral-vibe-cli-with-tools"
    public static let voxtralSmall2507: Self = "voxtral-small-2507"
    public static let voxtralSmallLatest: Self = "voxtral-small-latest"
    public static let zaiGlm52: Self = "zai-glm-5-2"
}

public struct MistralEmbeddingModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, Codable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.init(rawValue: value) }

    public static let mistralEmbed: Self = "mistral-embed"
    public static let mistralEmbed2312: Self = "mistral-embed-2312"
    public static let codestralEmbed: Self = "codestral-embed"
    public static let codestralEmbed2505: Self = "codestral-embed-2505"
}
