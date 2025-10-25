import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/assemblyai/src/assemblyai-error.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public struct AssemblyAIErrorPayload: Codable, Sendable {
    public struct ErrorBody: Codable, Sendable {
        public let message: String
        public let code: Int
    }

    public let error: ErrorBody
}

private let assemblyaiErrorJSONSchema: JSONValue = .object([
    "type": .string("object")
])

public let assemblyaiFailedResponseHandler: ResponseHandler<APICallError> = createJsonErrorResponseHandler(
    errorSchema: FlexibleSchema(
        Schema<AssemblyAIErrorPayload>.codable(
            AssemblyAIErrorPayload.self,
            jsonSchema: assemblyaiErrorJSONSchema
        )
    ),
    errorToMessage: { $0.error.message }
)
