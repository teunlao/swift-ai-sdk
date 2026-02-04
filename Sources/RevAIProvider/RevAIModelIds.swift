import Foundation

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/revai/src/revai-transcription-options.ts
// Upstream commit: f3a72bc2a
//===----------------------------------------------------------------------===//

public struct RevAITranscriptionModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}

public extension RevAITranscriptionModelId {
    static let machine: Self = "machine"
    static let lowCost: Self = "low_cost"
    static let fusion: Self = "fusion"
}

