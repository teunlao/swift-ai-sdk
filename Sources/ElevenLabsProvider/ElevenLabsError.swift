import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct ElevenLabsErrorPayload: Codable, Sendable {
    public struct ErrorBody: Codable, Sendable {
        public let message: String
        public let code: Double
    }

    public let error: ErrorBody
}

private let elevenLabsErrorJSONSchema: JSONValue = .object([
    "type": .string("object")
])

public let elevenLabsFailedResponseHandler: ResponseHandler<APICallError> = createJsonErrorResponseHandler(
    errorSchema: FlexibleSchema(
        Schema<ElevenLabsErrorPayload>.codable(
            ElevenLabsErrorPayload.self,
            jsonSchema: elevenLabsErrorJSONSchema
        )
    ),
    errorToMessage: { $0.error.message }
)
