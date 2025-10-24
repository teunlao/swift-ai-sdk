import Foundation
import AISDKProviderUtils
import AISDKProvider

// Mirrors `packages/lmnt/src/lmnt-error.ts`.
struct LMNTErrorData: Codable, Sendable {
    struct ErrorInfo: Codable, Sendable {
        let message: String
        let code: Int
    }
    let error: ErrorInfo
}

let lmntErrorDataSchema = FlexibleSchema(
    Schema<LMNTErrorData>.codable(
        LMNTErrorData.self,
        jsonSchema: .object(["type": .string("object")])
    )
)

public let lmntFailedResponseHandler = createJsonErrorResponseHandler(
    errorSchema: lmntErrorDataSchema,
    errorToMessage: { $0.error.message }
)
