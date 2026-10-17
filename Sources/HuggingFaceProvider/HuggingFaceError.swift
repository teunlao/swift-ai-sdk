import Foundation
import AISDKProvider
import AISDKProviderUtils
import OpenAICompatibleProvider

public typealias HuggingFaceErrorData = OpenAICompatibleErrorData

private struct APIErrorData: Decodable, Sendable {
    struct Payload: Decodable, Sendable {
        let message: String
        let type: String?
        let code: String?
        private enum CodingKeys: String, CodingKey { case message, type, code }
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            message = try container.decode(String.self, forKey: .message)
            type = try container.contains(.type) ? container.decode(String.self, forKey: .type) : nil
            code = try container.contains(.code) ? container.decode(String.self, forKey: .code) : nil
        }
    }
    let error: Payload
}

let huggingfaceFailedResponseHandler = createJsonErrorResponseHandler(
    errorSchema: FlexibleSchema(
        Schema<APIErrorData>.codable(APIErrorData.self, jsonSchema: .object(["type": .string("object")]))
    ),
    errorToMessage: { $0.error.message }
)
