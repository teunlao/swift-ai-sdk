import Foundation

/**
 Model not found or not available.

 Port of `@ai-sdk/gateway/src/errors/gateway-model-not-found-error.ts`.

 Minimal implementation for `wrapGatewayError` support.
 */
public struct GatewayModelNotFoundError: GatewayError, GatewayErrorMarker {
    public let name: String = "GatewayModelNotFoundError"
    public let type: String = "model_not_found"
    public let statusCode: Int
    public let modelId: String?
    public let cause: Error?
    public let message: String

    public init(
        message: String = "Model not found",
        statusCode: Int = 404,
        modelId: String? = nil,
        cause: Error? = nil
    ) {
        self.message = message
        self.statusCode = statusCode
        self.modelId = modelId
        self.cause = cause
    }

    public static func isInstance(_ error: Any?) -> Bool {
        return error is GatewayModelNotFoundError
    }
}
