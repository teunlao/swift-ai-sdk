import Foundation

/**
 Error thrown when a prompt is invalid.

 Port of `@ai-sdk/provider/src/errors/invalid-prompt-error.ts`.

 This error should be thrown by providers when they cannot process a prompt.
 Reasons include:
 - Empty messages array
 - Both prompt and messages are nil
 - Both prompt and messages are defined (XOR violation)
 - Invalid message structure

 ## Example
 ```swift
 // Empty messages
 throw InvalidPromptError(
     prompt: "Prompt(system: nil, prompt: nil, messages: nil)",
     message: "messages must not be empty"
 )

 // Both defined
 throw InvalidPromptError(
     prompt: "Prompt(system: \"...\", prompt: \"...\", messages: [...])",
     message: "prompt and messages cannot be defined at the same time"
 )
 ```
 */
public struct InvalidPromptError: Error, AISDKError, Sendable {
    public static let errorDomain = "AI_InvalidPromptError"
    public var name: String { Self.errorDomain }

    public let message: String
    public let prompt: String // description of invalid prompt
    public let cause: (any Error)?

    /**
     Creates an invalid prompt error.

     - Parameters:
       - prompt: Description of the invalid prompt (for debugging)
       - message: Error message explaining what is wrong
       - cause: Optional underlying error
     */
    public init(prompt: String, message: String, cause: (any Error)? = nil) {
        self.prompt = prompt
        self.cause = cause
        self.message = "Invalid prompt: \(message)"
    }

    public var errorDescription: String? {
        message
    }

    public func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "name": Self.errorDomain,
            "message": message,
            "prompt": prompt
        ]

        if let cause = cause {
            dict["cause"] = String(describing: cause)
        }

        return dict
    }

    /// Type guard to check if an error is an InvalidPromptError
    public static func isInstance(_ error: any Error) -> Bool {
        return error is InvalidPromptError
    }
}
