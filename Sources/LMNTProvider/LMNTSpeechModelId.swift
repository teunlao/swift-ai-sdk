import Foundation

/// LMNT speech model identifiers.
/// Mirrors `packages/lmnt/src/lmnt-speech-options.ts`.
public struct LMNTSpeechModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}

public extension LMNTSpeechModelId {
    static let aurora: Self = "aurora"
    static let blizzard: Self = "blizzard"
}

