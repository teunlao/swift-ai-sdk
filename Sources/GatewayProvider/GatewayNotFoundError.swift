import Foundation

public struct GatewayNotFoundError: GatewayError, GatewayErrorMarker, @unchecked Sendable {
    public let name = "GatewayNotFoundError"
    public let type = "not_found"
    public let statusCode: Int
    public let message: String
    public let cause: Error?
    public let generationId: String?

    public init(
        message: String = "Resource not found",
        statusCode: Int = 404,
        cause: Error? = nil,
        generationId: String? = nil
    ) {
        self.message = generationId.map { "\(message) [\($0)]" } ?? message
        self.statusCode = statusCode
        self.cause = cause
        self.generationId = generationId
    }

    public static func isInstance(_ error: Any?) -> Bool {
        Self.hasMarker(error) && error is Self
    }
}
