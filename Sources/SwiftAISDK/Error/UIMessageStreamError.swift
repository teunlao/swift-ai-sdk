import Foundation
import AISDKProvider

/**
 Error thrown when a UI message stream contains invalid or out-of-sequence chunks.

 Port of `@ai-sdk/ai/src/error/ui-message-stream-error.ts`.
 */
public struct UIMessageStreamError: AISDKError, Sendable {
    public static let errorDomain = "vercel.ai.error.AI_UIMessageStreamError"

    public let name = "AI_UIMessageStreamError"
    public let message: String
    public let cause: (any Error)? = nil

    /// The type of chunk that caused the error.
    public let chunkType: String

    /// The ID associated with the failing chunk.
    public let chunkId: String

    public init(
        chunkType: String,
        chunkId: String,
        message: String
    ) {
        self.chunkType = chunkType
        self.chunkId = chunkId
        self.message = message
    }

    public static func isInstance(_ error: any Error) -> Bool {
        hasMarker(error, marker: errorDomain)
    }

    public var description: String { message }
}
