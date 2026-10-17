import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct OpenResponsesErrorData: Codable, Sendable, Equatable {
    public struct ErrorPayload: Codable, Sendable, Equatable {
        public let message: String
        public let type: String?
        public let param: String?
        public let code: String?
        private let present: Set<CodingKeys>
        private enum CodingKeys: String, CodingKey { case message, type, param, code }

        public init(message: String, type: String? = nil, param: String? = nil, code: String? = nil) {
            self.message = message
            self.type = type
            self.param = param
            self.code = code
            var fields: Set<CodingKeys> = [.message]
            if type != nil { fields.insert(.type) }
            if param != nil { fields.insert(.param) }
            if code != nil { fields.insert(.code) }
            present = fields
        }
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            message = try container.decode(String.self, forKey: .message)
            type = try container.decodeIfPresent(String.self, forKey: .type)
            param = try container.decodeIfPresent(String.self, forKey: .param)
            code = try container.decodeIfPresent(String.self, forKey: .code)
            present = Set([CodingKeys.message, .type, .param, .code].filter { container.contains($0) })
        }
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(message, forKey: .message)
            if present.contains(.type) { try container.encode(type, forKey: .type) }
            if present.contains(.param) { try container.encode(param, forKey: .param) }
            if present.contains(.code) { try container.encode(code, forKey: .code) }
        }
    }
    public let error: ErrorPayload
    public init(error: ErrorPayload) { self.error = error }
}

public struct OpenResponsesResponseError: Sendable, Equatable {
    public let message: String
    public let code: String?
    public let fields: JSONObject

    public init(message: String, code: String? = nil, fields: JSONObject = [:]) {
        self.message = message
        self.code = code
        var values = fields
        values["message"] = .string(message)
        if let code { values["code"] = .string(code) }
        self.fields = values
    }
}

public struct OpenResponsesResponseErrorMetadata: Sendable, Equatable {
    public var statusCode: Int?
    public var isRetryable: Bool?
    public init(statusCode: Int? = nil, isRetryable: Bool? = nil) {
        self.statusCode = statusCode
        self.isRetryable = isRetryable
    }
}

let openResponsesErrorDataSchema = FlexibleSchema(Schema<OpenResponsesErrorData>.codable(OpenResponsesErrorData.self, jsonSchema: ["type": "object"]))
let openResponsesFailedResponseHandler = createJsonErrorResponseHandler(errorSchema: openResponsesErrorDataSchema, errorToMessage: { $0.error.message })
