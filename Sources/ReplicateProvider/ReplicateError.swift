import Foundation
import AISDKProvider
import AISDKProviderUtils

/// Error payload returned by Replicate on non-2xx responses.
private struct ReplicateErrorPayload: Codable, Sendable {
    let detail: String?
    let error: String?
}

private let replicateErrorSchema = FlexibleSchema(
    Schema<ReplicateErrorPayload>.codable(
        ReplicateErrorPayload.self,
        jsonSchema: .object(["type": .string("object")])
    )
)

/// Failed response handler for Replicate HTTP APIs.
/// Mirrors `packages/replicate/src/replicate-error.ts`.
public let replicateFailedResponseHandler = createJsonErrorResponseHandler(
    errorSchema: replicateErrorSchema,
    errorToMessage: { payload in
        payload.detail ?? payload.error ?? "Unknown Replicate error"
    }
)

