import Foundation

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/hume/src/hume-speech-model.ts (implicit model ids)
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

/// Hume speech model identifiers.
/// Upstream currently exposes a single unnamed model, represented by the empty string.
public struct HumeSpeechModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}

public extension HumeSpeechModelId {
    /// Default Hume speech model.
    static let `default`: Self = ""
}
