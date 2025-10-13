import Foundation

/**
 * Type validation failed.
 *
 * Swift port of TypeScript `TypeValidationError`.
 */
public struct TypeValidationError: AISDKError, @unchecked Sendable {
    public static let errorDomain = "vercel.ai.error.AI_TypeValidationError"

    public let name = "AI_TypeValidationError"
    public let message: String
    public let cause: (any Error)?
    public let value: Any?

    public init(value: Any?, cause: any Error) {
        self.value = value
        self.cause = cause

        // Try to serialize value for the error message
        let valueString: String
        if let value = value {
            // Try JSON serialization, but wrap primitives first
            if JSONSerialization.isValidJSONObject(value) {
                if let jsonData = try? JSONSerialization.data(withJSONObject: value, options: []),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    valueString = jsonString
                } else {
                    valueString = String(describing: value)
                }
            } else {
                // For primitives (Int, String, Bool, etc), use direct representation
                valueString = String(describing: value)
            }
        } else {
            valueString = "null"
        }

        self.message = """
            Type validation failed: \
            Value: \(valueString).
            Error message: \(getErrorMessage(cause))
            """
    }

    /// Check if an error is an instance of TypeValidationError
    public static func isInstance(_ error: any Error) -> Bool {
        SwiftAISDK.hasMarker(error, marker: errorDomain)
    }

    /**
     * Wraps an error into a TypeValidationError.
     * If the cause is already a TypeValidationError with the same value, it returns the cause.
     * Otherwise, it creates a new TypeValidationError.
     */
    public static func wrap(value: Any?, cause: any Error) -> TypeValidationError {
        // Check if cause is already TypeValidationError with same value
        if let tvError = cause as? TypeValidationError,
           areValuesEqual(tvError.value, value) {
            return tvError
        }
        return TypeValidationError(value: value, cause: cause)
    }

    /// Helper to compare two Any? values
    private static func areValuesEqual(_ lhs: Any?, _ rhs: Any?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case (.some(let l), .some(let r)):
            // Try string representation comparison as fallback
            return String(describing: l) == String(describing: r)
        default:
            return false
        }
    }
}
