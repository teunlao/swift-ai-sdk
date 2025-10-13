import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Wraps Gateway errors in AISDKError for better error messaging.

 Port of `@ai-sdk/ai/src/prompt/wrap-gateway-error.ts`.

 When a Vercel AI Gateway error occurs, this function wraps it in an AISDKError
 with a helpful message about using AI SDK providers directly.

 - Parameter error: The error to check and potentially wrap
 - Returns: The original error, or wrapped version if it's a Gateway error

 ## Example
 ```swift
 do {
     try await someGatewayOperation()
 } catch {
     throw wrapGatewayError(error)
 }
 ```
 */
public func wrapGatewayError(_ error: Any?) -> Any? {
    // Check if error is GatewayAuthenticationError or GatewayModelNotFoundError
    if GatewayAuthenticationError.isInstance(error) ||
       GatewayModelNotFoundError.isInstance(error) {
        return GatewayErrorWrapper(
            message: "Vercel AI Gateway access failed. " +
                    "If you want to use AI SDK providers directly, use the providers, e.g. @ai-sdk/openai, " +
                    "or register a different global default provider.",
            cause: error as? Error
        )
    }

    return error
}

// MARK: - Gateway Error Wrapper

/**
 AISDKError wrapper for Gateway errors.

 Swift adaptation: Concrete struct implementing AISDKError protocol.
 TypeScript uses `new AISDKError({name: 'GatewayError', ...})`.
 */
public struct GatewayErrorWrapper: AISDKError {
    public static let errorDomain = "vercel.ai.GatewayError"

    public let name: String = "GatewayError"
    public let message: String
    public let cause: Error?

    public init(message: String, cause: Error?) {
        self.message = message
        self.cause = cause
    }
}
