import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/gateway/src/errors/gateway-model-not-found-error.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

/// Model not found or not available.
public struct GatewayModelNotFoundError: GatewayError, GatewayErrorMarker, @unchecked Sendable {
    public let name = "GatewayModelNotFoundError"
    public let type = "model_not_found"
    public let statusCode: Int
    public let message: String
    public let modelId: String?
    public let cause: Error?

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
        return Self.hasMarker(error) && error is GatewayModelNotFoundError
    }
}
