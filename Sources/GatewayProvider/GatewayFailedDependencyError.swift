import Foundation

public struct GatewayFailedDependencyError: GatewayError, GatewayErrorMarker, @unchecked Sendable {
    public let name = "GatewayFailedDependencyError"
    public let type = "failed_dependency"
    public let statusCode: Int
    public let message: String
    public let cause: Error?
    public let generationId: String?

    public init(
        message: String = "Failed dependency",
        statusCode: Int = 424,
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
