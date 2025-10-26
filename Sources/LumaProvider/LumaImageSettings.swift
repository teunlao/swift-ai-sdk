import Foundation

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/luma/src/luma-image-settings.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

/// Configuration settings for Luma image generation polling behavior.
/// Mirrors `LumaImageSettings` interface from upstream TypeScript.
public struct LumaImageSettings: Sendable {
    /// Override the polling interval in milliseconds (default 500).
    public let pollIntervalMillis: Int?

    /// Override the maximum number of polling attempts (default 120).
    public let maxPollAttempts: Int?

    public init(pollIntervalMillis: Int? = nil, maxPollAttempts: Int? = nil) {
        self.pollIntervalMillis = pollIntervalMillis
        self.maxPollAttempts = maxPollAttempts
    }
}
