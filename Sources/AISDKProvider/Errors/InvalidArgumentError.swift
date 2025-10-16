import Foundation

/**
 A function argument is invalid.

 Port of `@ai-sdk/provider/src/errors/invalid-argument-error.ts` with
 additional initializer matching `@ai-sdk/ai/src/error/invalid-argument-error.ts`.
 */
public struct InvalidArgumentError: AISDKError, Sendable {
    public static let errorDomain = "vercel.ai.error.AI_InvalidArgumentError"

    public let name = "AI_InvalidArgumentError"
    public let message: String
    public let cause: (any Error)?

    /// Argument name for provider usage.
    public let argument: String

    /// Optional value associated with the parameter (AI SDK initializer).
    public let value: JSONValue?

    /// Alias for `argument` to match AI SDK naming.
    public var parameter: String { argument }

    public init(
        argument: String,
        message: String,
        cause: (any Error)? = nil
    ) {
        self.argument = argument
        self.message = message
        self.cause = cause
        self.value = nil
    }

    public init(
        parameter: String,
        value: JSONValue,
        message: String,
        cause: (any Error)? = nil
    ) {
        self.argument = parameter
        self.value = value
        self.cause = cause
        self.message = "Invalid argument for parameter \(parameter): \(message)"
    }

    /// Check if an error is an instance of InvalidArgumentError
    public static func isInstance(_ error: any Error) -> Bool {
        hasMarker(error, marker: errorDomain)
    }
}
