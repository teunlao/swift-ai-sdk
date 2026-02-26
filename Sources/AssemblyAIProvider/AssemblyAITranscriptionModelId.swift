import Foundation

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/assemblyai/src/assemblyai-transcription-settings.ts
// Upstream commit: 73d5c5920e
//===----------------------------------------------------------------------===//

public struct AssemblyAITranscriptionModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}

public extension AssemblyAITranscriptionModelId {
    static let best: Self = "best"
    static let nano: Self = "nano"
}
