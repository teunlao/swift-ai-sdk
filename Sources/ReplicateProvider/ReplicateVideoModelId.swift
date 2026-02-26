import Foundation

/// Replicate video model identifier.
/// Mirrors `packages/replicate/src/replicate-video-settings.ts`.
public struct ReplicateVideoModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}

// MARK: - Known model IDs (from upstream)
// Mirrors `packages/replicate/src/replicate-video-settings.ts`.
public extension ReplicateVideoModelId {
    static let minimaxVideo01: Self = "minimax/video-01"
    static let minimaxVideo01Versioned: Self = "minimax/video-01:6c1e4171-288a-4ca2-a738-894f0e87699d"
    static let stabilityStableVideoDiffusionVersioned: Self =
        "stability-ai/stable-video-diffusion:3f0457e4619daac51203dedb472816fd4af51f3149fa7a9e0b5ffcf1b8172438"
}

