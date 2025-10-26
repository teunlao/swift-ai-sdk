import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/luma/src/luma-image-model.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public struct LumaErrorContext: Codable, Sendable {
    public let expected: String?
}

public struct LumaErrorDetail: Codable, Sendable {
    public let type: String
    public let loc: [String]
    public let msg: String
    public let input: String
    public let ctx: LumaErrorContext?
}

public struct LumaErrorData: Codable, Sendable {
    public let detail: [LumaErrorDetail]
}

private let lumaErrorJSONSchema: JSONValue = .object([
    "type": .string("object")
])

public let lumaFailedResponseHandler: ResponseHandler<APICallError> = createJsonErrorResponseHandler(
    errorSchema: FlexibleSchema(
        Schema<LumaErrorData>.codable(
            LumaErrorData.self,
            jsonSchema: lumaErrorJSONSchema
        )
    ),
    errorToMessage: { error in
        error.detail.first?.msg ?? "Unknown error"
    }
)
