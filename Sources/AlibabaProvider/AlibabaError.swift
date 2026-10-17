import AISDKProvider
import AISDKProviderUtils

public struct AlibabaErrorData: Codable, Sendable, Equatable {
    public struct Payload: Codable, Sendable, Equatable {
        public let message: String
        public let code: String?
        public let type: String?
        private let present: Set<Keys>
        private enum Keys: String, CodingKey { case message, code, type }
        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: Keys.self)
            message = try values.decode(String.self, forKey: .message)
            code = try values.decodeIfPresent(String.self, forKey: .code)
            type = try values.decodeIfPresent(String.self, forKey: .type)
            present = Set([Keys.message, .code, .type].filter(values.contains))
        }
        public func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: Keys.self)
            try values.encode(message, forKey: .message)
            if present.contains(.code) { try values.encode(code, forKey: .code) }
            if present.contains(.type) { try values.encode(type, forKey: .type) }
        }
    }
    public let error: Payload
}
public let alibabaFailedResponseHandler = createJsonErrorResponseHandler(
    errorSchema: FlexibleSchema(Schema<AlibabaErrorData>.codable(AlibabaErrorData.self, jsonSchema: ["type": "object"])),
    errorToMessage: { $0.error.message }
)
