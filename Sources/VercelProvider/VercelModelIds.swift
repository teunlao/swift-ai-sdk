import Foundation

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/vercel/src/vercel-chat-options.ts
// Upstream commit: f3a72bc2a
//===----------------------------------------------------------------------===//

/// Wrapper type for Vercel (v0) chat model identifiers.
/// Mirrors `packages/vercel/src/vercel-chat-options.ts`.
public struct VercelChatModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}

// MARK: - Known model identifiers (mirrors packages/vercel/src/vercel-chat-options.ts)

public extension VercelChatModelId {
    static let v0_1_0_md: Self = "v0-1.0-md"
    static let v0_1_5_md: Self = "v0-1.5-md"
    static let v0_1_5_lg: Self = "v0-1.5-lg"
}

