/**
 Error thrown when an invalid stream part is encountered during streaming.

 Port of `@ai-sdk/ai/src/error/invalid-stream-part-error.ts`.

 This error is thrown when processing stream parts that don't match the expected format
 or contain invalid data.
 */

import Foundation
import AISDKProvider

/// Error name constant
private let errorName = "AI_InvalidStreamPartError"

/// Error domain marker (equivalent to Symbol.for(marker) in TypeScript)
private let errorMarker = "vercel.ai.error.\(errorName)"

/**
 Error thrown when an invalid stream part is encountered.

 Note: In the Swift port, we use `JSONValue` to represent the stream chunk
 since the full `SingleRequestTextStreamPart` type (from Block E: Generate Text)
 is not yet fully implemented. This provides adequate functionality for error
 reporting while maintaining simplicity.
 */
public struct InvalidStreamPartError: AISDKError, Sendable {
    public static let errorDomain: String = errorMarker
    public let name: String = errorName
    public let message: String
    public let cause: (any Error)?

    /// The invalid stream chunk that caused the error
    public let chunk: JSONValue

    public init(chunk: JSONValue, message: String, cause: (any Error)? = nil) {
        self.chunk = chunk
        self.message = message
        self.cause = cause
    }
}

// MARK: - Type Checking

/// Check if an error is an InvalidStreamPartError
public func isInvalidStreamPartError(_ error: any Error) -> Bool {
    hasMarker(error, marker: errorMarker)
}
