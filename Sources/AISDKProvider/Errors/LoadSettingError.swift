/**
 * Error loading setting.
 *
 * Swift port of TypeScript `LoadSettingError`.
 */
public struct LoadSettingError: AISDKError, Sendable {
    public static let errorDomain = "vercel.ai.error.AI_LoadSettingError"

    public let name = "AI_LoadSettingError"
    public let message: String
    public let cause: (any Error)? = nil

    public init(message: String) {
        self.message = message
    }

    /// Check if an error is an instance of LoadSettingError
    public static func isInstance(_ error: any Error) -> Bool {
        hasMarker(error, marker: errorDomain)
    }
}
