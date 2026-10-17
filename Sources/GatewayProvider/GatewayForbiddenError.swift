import Foundation

public struct GatewayForbiddenError: GatewayError, GatewayErrorMarker, @unchecked Sendable {
    public let name = "GatewayForbiddenError"
    public let type = "forbidden"
    public let statusCode: Int
    public let message: String
    public let cause: Error?
    public let generationId: String?
    public let ruleId: String?

    public init(
        message: String = "Forbidden",
        statusCode: Int = 403,
        cause: Error? = nil,
        generationId: String? = nil,
        ruleId: String? = nil
    ) {
        self.message = generationId.map { "\(message) [\($0)]" } ?? message
        self.statusCode = statusCode
        self.cause = cause
        self.generationId = generationId
        self.ruleId = ruleId
    }

    public static func isInstance(_ error: Any?) -> Bool {
        Self.hasMarker(error) && error is Self
    }
}
