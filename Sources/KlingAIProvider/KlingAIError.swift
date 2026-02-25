import Foundation
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/klingai/src/klingai-error.ts
// Upstream commit: 73d5c59
//===----------------------------------------------------------------------===//

struct KlingAIErrorData: Codable, Sendable {
    let code: Double
    let message: String
}

private let klingaiErrorDataSchema = FlexibleSchema(
    Schema<KlingAIErrorData>.codable(
        KlingAIErrorData.self,
        jsonSchema: .object(["type": .string("object")])
    )
)

let klingaiFailedResponseHandler = createJsonErrorResponseHandler(
    errorSchema: klingaiErrorDataSchema,
    errorToMessage: { data in data.message }
)

