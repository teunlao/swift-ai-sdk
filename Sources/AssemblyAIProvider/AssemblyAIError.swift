import AISDKProvider
import AISDKProviderUtils

struct AssemblyAIErrorData: Codable, Sendable {
    struct ErrorBody: Codable, Sendable { let message: String; let code: Double }
    let error: ErrorBody
}
let assemblyaiFailedResponseHandler = createJsonErrorResponseHandler(
    errorSchema: FlexibleSchema(Schema<AssemblyAIErrorData>.codable(AssemblyAIErrorData.self, jsonSchema: ["type": "object"])),
    errorToMessage: { $0.error.message }
)
