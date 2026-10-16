import Foundation
import AISDKProvider
import AISDKProviderUtils

/// Error payload returned by Replicate on non-2xx responses.
private struct ReplicateErrorPayload: Decodable, Sendable {
    let detail: String?
    let error: String?
    private enum CodingKeys: String, CodingKey { case detail, error }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        detail = values.contains(.detail) ? try values.decode(String.self, forKey: .detail) : nil
        error = values.contains(.error) ? try values.decode(String.self, forKey: .error) : nil
    }
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

