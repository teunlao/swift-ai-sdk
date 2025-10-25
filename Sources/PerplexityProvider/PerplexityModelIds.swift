import Foundation

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/perplexity/src/perplexity-language-model-options.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public struct PerplexityLanguageModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}

public extension PerplexityLanguageModelId {
    static let sonarDeepResearch: Self = "sonar-deep-research"
    static let sonarReasoningPro: Self = "sonar-reasoning-pro"
    static let sonarReasoning: Self = "sonar-reasoning"
    static let sonarPro: Self = "sonar-pro"
    static let sonar: Self = "sonar"
}
