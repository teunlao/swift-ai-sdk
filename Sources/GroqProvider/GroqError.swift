import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct GroqErrorData: Sendable, Equatable, Codable {
    public struct ErrorBody: Sendable, Equatable, Codable {
        public let message: String
        public let type: String
    }

    public let error: ErrorBody
}

private let groqErrorJSONSchema: JSONValue = .object([
    "type": .string("object")
])

public let groqFailedResponseHandler = createJsonErrorResponseHandler(
    errorSchema: FlexibleSchema(
        Schema<GroqErrorData>.codable(
            GroqErrorData.self,
            jsonSchema: groqErrorJSONSchema
        )
    ),
    errorToMessage: { $0.error.message }
)
