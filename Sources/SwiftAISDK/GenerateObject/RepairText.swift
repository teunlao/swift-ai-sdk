import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Describes errors that can trigger repair of a language model response.

 Port of `@ai-sdk/ai/src/generate-object/repair-text.ts`.
 */
public enum RepairTextError: Sendable {
    case parse(JSONParseError)
    case validation(TypeValidationError)

    /// Underlying error value.
    public var underlyingError: any Error {
        switch self {
        case .parse(let error):
            return error
        case .validation(let error):
            return error
        }
    }
}

/**
 Input passed to a repair function to attempt recovering JSON output.

 Port of `@ai-sdk/ai/src/generate-object/repair-text.ts`.
 */
public struct RepairTextOptions: Sendable {
    /// Original text returned by the model.
    public let text: String

    /// Error that occurred during parsing or validation.
    public let error: RepairTextError

    public init(text: String, error: RepairTextError) {
        self.text = text
        self.error = error
    }
}

/// Repair function that can fix malformed JSON produced by the model.
///
/// Should return the repaired text or `nil` if the text cannot be repaired.
public typealias RepairTextFunction = @Sendable (_ options: RepairTextOptions) async -> String?
