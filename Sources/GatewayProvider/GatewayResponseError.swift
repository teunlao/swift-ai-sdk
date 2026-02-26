import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/gateway/src/errors/gateway-response-error.ts
// Upstream commit: 73d5c5920
//===----------------------------------------------------------------------===//

/// Gateway response parsing error.
public struct GatewayResponseError: GatewayError, GatewayErrorMarker, @unchecked Sendable {
    public let name = "GatewayResponseError"
    public let type = "response_error"
    public let statusCode: Int
    public let message: String
    public let response: AnySendable?
    public let validationError: TypeValidationError?
    public let cause: Error?
    public let generationId: String?

    public init(
        message: String = "Invalid response from Gateway",
        statusCode: Int = 502,
        response: Any? = nil,
        validationError: TypeValidationError? = nil,
        cause: Error? = nil,
        generationId: String? = nil
    ) {
        self.generationId = generationId
        self.message = generationId.map { "\(message) [\($0)]" } ?? message
        self.statusCode = statusCode
        self.response = response.map(AnySendable.init)
        self.validationError = validationError
        self.cause = cause
    }

    public static func isInstance(_ error: Any?) -> Bool {
        return Self.hasMarker(error) && error is GatewayResponseError
    }
}
