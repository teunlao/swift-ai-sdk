import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/gateway/src/errors/gateway-timeout-error.ts
// Upstream commit: 73d5c5920
//===----------------------------------------------------------------------===//

/// Client request timed out before receiving a response.
public struct GatewayTimeoutError: GatewayError, GatewayErrorMarker, @unchecked Sendable {
    public let name = "GatewayTimeoutError"
    public let type = "timeout_error"
    public let statusCode: Int
    public let message: String
    public let cause: Error?
    public let generationId: String?

    public init(
        message: String = "Request timed out",
        statusCode: Int = 408,
        cause: Error? = nil,
        generationId: String? = nil
    ) {
        self.generationId = generationId
        self.message = generationId.map { "\(message) [\($0)]" } ?? message
        self.statusCode = statusCode
        self.cause = cause
    }

    public static func isInstance(_ error: Any?) -> Bool {
        return Self.hasMarker(error) && error is GatewayTimeoutError
    }

    /// Creates a helpful timeout error message with troubleshooting guidance.
    public static func createTimeoutError(
        originalMessage: String,
        statusCode: Int = 408,
        cause: Error? = nil,
        generationId: String? = nil
    ) -> GatewayTimeoutError {
        let message = "Gateway request timed out: \(originalMessage)\n\n    This is a client-side timeout. To resolve this, increase your timeout configuration: https://vercel.com/docs/ai-gateway/capabilities/video-generation#extending-timeouts-for-node.js"

        return GatewayTimeoutError(
            message: message,
            statusCode: statusCode,
            cause: cause,
            generationId: generationId
        )
    }
}
