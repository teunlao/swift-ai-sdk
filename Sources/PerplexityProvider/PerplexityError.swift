import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/perplexity/src/perplexity-language-model.ts (error schema)
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public struct PerplexityErrorPayload: Codable, Sendable {
    public struct ErrorBody: Codable, Sendable {
        public let code: Int
        public let message: String?
        public let type: String?
    }

    public let error: ErrorBody
}

private let genericJSONObjectSchema: JSONValue = .object([
    "type": .string("object")
])

public let perplexityFailedResponseHandler: ResponseHandler<APICallError> = createJsonErrorResponseHandler(
    errorSchema: FlexibleSchema(
        Schema<PerplexityErrorPayload>.codable(
            PerplexityErrorPayload.self,
            jsonSchema: genericJSONObjectSchema
        )
    ),
    errorToMessage: { payload in
        payload.error.message ?? payload.error.type ?? "unknown error"
    }
)
