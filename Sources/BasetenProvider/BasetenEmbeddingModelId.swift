import Foundation

/// Baseten embedding model identifier wrapper.
/// Mirrors `packages/baseten/src/baseten-embedding-options.ts`.
public struct BasetenEmbeddingModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}
