import AISDKProvider
import AISDKProviderUtils

public struct DeepgramErrorData: Codable, Sendable, Equatable {
    public let errCode: String
    public let errMsg: String
    public let requestId: String?
    public init(errCode: String, errMsg: String, requestId: String? = nil) {
        self.errCode = errCode
        self.errMsg = errMsg
        self.requestId = requestId
    }
    private enum CodingKeys: String, CodingKey { case errCode = "err_code", errMsg = "err_msg", requestId = "request_id" }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        errCode = try values.decode(String.self, forKey: .errCode)
        errMsg = try values.decode(String.self, forKey: .errMsg)
        requestId = values.contains(.requestId) ? try values.decode(String.self, forKey: .requestId) : nil
    }
}

let deepgramFailedResponseHandler = createJsonErrorResponseHandler(
    errorSchema: FlexibleSchema(Schema<DeepgramErrorData>.codable(DeepgramErrorData.self, jsonSchema: ["type": "object"])),
    errorToMessage: { $0.errMsg }
)
