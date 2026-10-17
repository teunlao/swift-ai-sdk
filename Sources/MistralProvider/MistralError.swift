import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/mistral/src/mistral-error.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public struct MistralErrorData: Codable, Sendable {
    public let object: String
    public let message: String
    public let type: String
    public let param: String?
    public let code: String?

    private enum CodingKeys: String, CodingKey {
        case object, message, type, param, code
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        object = try container.decode(String.self, forKey: .object)
        guard object == "error" else {
            throw DecodingError.dataCorruptedError(forKey: .object, in: container, debugDescription: "Expected 'error' object")
        }
        message = try container.decode(String.self, forKey: .message)
        type = try container.decode(String.self, forKey: .type)
        param = try container.decode(String?.self, forKey: .param)
        code = try container.decode(String?.self, forKey: .code)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(object, forKey: .object)
        try container.encode(message, forKey: .message)
        try container.encode(type, forKey: .type)
        try container.encode(param, forKey: .param)
        try container.encode(code, forKey: .code)
    }
}

private let genericJSONObjectSchema: JSONValue = .object([
    "type": .string("object")
])

public let mistralFailedResponseHandler: ResponseHandler<APICallError> = createJsonErrorResponseHandler(
    errorSchema: FlexibleSchema(
        Schema<MistralErrorData>.codable(
            MistralErrorData.self,
            jsonSchema: genericJSONObjectSchema
        )
    ),
    errorToMessage: { $0.message }
)
