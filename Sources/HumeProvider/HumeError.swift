import Foundation
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/hume/src/hume-error.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

private struct HumeErrorBody: Codable, Sendable {
    let message: String
    let code: Int
}

private struct HumeErrorData: Codable, Sendable {
    let error: HumeErrorBody
}

private let humeErrorDataSchema = FlexibleSchema(
    Schema<HumeErrorData>.codable(
        HumeErrorData.self,
        jsonSchema: .object(["type": .string("object")])
    )
)

let humeFailedResponseHandler = createJsonErrorResponseHandler(
    errorSchema: humeErrorDataSchema,
    errorToMessage: { $0.error.message }
)
