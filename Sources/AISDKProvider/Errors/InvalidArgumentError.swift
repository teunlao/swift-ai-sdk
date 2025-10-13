/**
 A function argument is invalid.

 Port of `@ai-sdk/ai/src/error/invalid-argument-error.ts`.
 */
public struct InvalidArgumentError: AISDKError, Sendable {
    public static let errorDomain = "vercel.ai.error.AI_InvalidArgumentError"

    public let name = "AI_InvalidArgumentError"
    public let message: String
    public let cause: (any Error)?

    /// The parameter name that is invalid
    public let parameter: String

    /// The value that was provided for the parameter (can be any type)
    public let value: JSONValue?

    public init(
        parameter: String,
        value: JSONValue? = nil,
        message: String,
        cause: (any Error)? = nil
    ) {
        self.parameter = parameter
        self.value = value
        self.message = "Invalid argument for parameter \(parameter): \(message)"
        self.cause = cause
    }

    /// Check if an error is an instance of InvalidArgumentError
    public static func isInstance(_ error: any Error) -> Bool {
        hasMarker(error, marker: errorDomain)
    }
}
