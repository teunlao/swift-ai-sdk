/**
 * Error loading API key.
 *
 * Swift port of TypeScript `LoadAPIKeyError`.
 */
public struct LoadAPIKeyError: AISDKError, Sendable {
    public static let errorDomain = "vercel.ai.error.AI_LoadAPIKeyError"

    public let name = "AI_LoadAPIKeyError"
    public let message: String
    public let cause: (any Error)? = nil

    public init(message: String) {
        self.message = message
    }

    /// Check if an error is an instance of LoadAPIKeyError
    public static func isInstance(_ error: any Error) -> Bool {
        SwiftAISDK.hasMarker(error, marker: errorDomain)
    }
}
