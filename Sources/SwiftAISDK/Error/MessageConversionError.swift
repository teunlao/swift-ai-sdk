/**
 Error thrown when a message cannot be converted from UI format to the provider format.

 Port of `@ai-sdk/ai/src/prompt/message-conversion-error.ts`.

 This error is thrown when converting UI messages fails, typically due to invalid content
 or unsupported message formats.
 */

import Foundation
import AISDKProvider

/// Error name constant
private let errorName = "AI_MessageConversionError"

/// Error domain marker (equivalent to Symbol.for(marker) in TypeScript)
private let errorMarker = "vercel.ai.error.\(errorName)"

/**
 Error thrown when a message cannot be converted from UI format to the provider format.

 Note: In the Swift port, we use `JSONValue` to represent the original message structure
 since the full `UIMessage` type (from Block R: UI Integration) is not yet implemented.
 This provides adequate functionality for error reporting while maintaining simplicity.
 */
public struct MessageConversionError: AISDKError, Sendable {
    public static let errorDomain: String = errorMarker
    public let name: String = errorName
    public let message: String
    public let cause: (any Error)?

    /// The original message that failed conversion (using JSONValue as placeholder for UIMessage)
    public let originalMessage: JSONValue

    public init(originalMessage: JSONValue, message: String, cause: (any Error)? = nil) {
        self.originalMessage = originalMessage
        self.message = message
        self.cause = cause
    }
}

// MARK: - Type Checking

/// Check if an error is a MessageConversionError
public func isMessageConversionError(_ error: any Error) -> Bool {
    hasMarker(error, marker: errorMarker)
}
