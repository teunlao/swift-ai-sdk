import Foundation
import AISDKProvider
import AISDKProviderUtils

/// Codable representation of OpenAI error payloads.
/// Mirrors the structure defined in `openai-error.ts`.
public struct OpenAIErrorData: Codable, Sendable, Equatable {
    public struct ErrorPayload: Codable, Sendable, Equatable {
        public let message: String
        public let type: String?
        public let param: JSONValue?
        public let code: OpenAIErrorCode?
        // Stream classification distinguishes omitted keys from explicit nulls.
        private let nullFields: Set<CodingKeys>

        private enum CodingKeys: String, CodingKey, Hashable, Sendable {
            case message, type, param, code
        }

        public init(
            message: String,
            type: String? = nil,
            param: JSONValue? = nil,
            code: OpenAIErrorCode? = nil
        ) {
            self.message = message
            self.type = type
            self.param = param
            self.code = code
            self.nullFields = []
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            message = try container.decode(String.self, forKey: .message)
            type = try container.decodeIfPresent(String.self, forKey: .type)
            code = try container.decodeIfPresent(OpenAIErrorCode.self, forKey: .code)
            if container.contains(.param) {
                param = try container.decode(JSONValue.self, forKey: .param)
            } else {
                param = Optional<JSONValue>.none
            }
            var nulls: Set<CodingKeys> = []
            for key in [CodingKeys.type, .code] where container.contains(key) {
                if try container.decodeNil(forKey: key) { nulls.insert(key) }
            }
            nullFields = nulls
        }

        public func encode(to encoder: Encoder) throws {
            try jsonValue.encode(to: encoder)
        }

        var jsonValue: JSONValue {
            var result: [String: JSONValue] = ["message": .string(message)]
            if let type { result["type"] = .string(type) }
            else if nullFields.contains(.type) { result["type"] = .null }
            if let param { result["param"] = param }
            switch code {
            case .string(let value): result["code"] = .string(value)
            case .number(let value): result["code"] = .number(value)
            case nil:
                if nullFields.contains(.code) { result["code"] = .null }
            }
            return .object(result)
        }
    }

    public let error: ErrorPayload

    public init(error: ErrorPayload) {
        self.error = error
    }
}

/// Union type representing either a string or numeric error code.
public enum OpenAIErrorCode: Sendable, Equatable {
    case string(String)
    case number(Double)
}

extension OpenAIErrorCode: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
            return
        }
        if let intValue = try? container.decode(Int.self) {
            self = .number(Double(intValue))
            return
        }
        if let doubleValue = try? container.decode(Double.self) {
            self = .number(doubleValue)
            return
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported OpenAI error code value")
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        }
    }
}

private let openAIErrorJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "required": .array([.string("error")]),
    "additionalProperties": .bool(false),
    "properties": .object([
        "error": .object([
            "type": .string("object"),
            "required": .array([.string("message")]),
            "additionalProperties": .bool(true),
            "properties": .object([
                "message": .object(["type": .string("string")]),
                "type": .object(["type": .array([.string("string"), .string("null")])]),
                "param": .bool(true),
                "code": .object(["type": .array([.string("string"), .string("number"), .string("null")])])
            ])
        ])
    ])
])

public let openAIErrorDataSchema = FlexibleSchema(
    Schema<OpenAIErrorData>.codable(
        OpenAIErrorData.self,
        jsonSchema: openAIErrorJSONSchema
    )
)

public let openAIFailedResponseHandler = createJsonErrorResponseHandler(
    errorSchema: openAIErrorDataSchema,
    errorToMessage: { $0.error.message }
)

func createOpenAIProviderStreamError(_ frame: JSONValue) -> ProviderStreamError? {
    guard let error = parseOpenAIStreamError(frame) else { return nil }
    let statusCode = openAIStreamErrorStatus(error.code, type: error.type)
    let isQuotaError = error.code == .string("insufficient_quota") || error.type == "insufficient_quota"
    return ProviderStreamError(
        message: error.message,
        type: error.type,
        code: error.code,
        statusCode: statusCode,
        isRetryable: !isQuotaError && (statusCode == 408 || statusCode == 409 || statusCode == 429 || statusCode >= 500),
        data: frame
    )
}

private func parseOpenAIStreamError(_ frame: JSONValue) -> (message: String, type: String?, code: ProviderStreamError.Code?)? {
    guard case .object(let value) = frame else { return nil }
    if value["type"] == .string("response.failed") {
        guard case .object(let response)? = value["response"],
              case .object(let error)? = response["error"],
              case .string(let message)? = error["message"] else { return nil }
        return (message, "response.failed", openAIStreamErrorCode(error["code"]))
    }

    let error: [String: JSONValue]
    let isNested: Bool
    switch value["error"] {
    case .object(let nested):
        error = nested
        isNested = true
    case .array:
        return nil
    default:
        error = value
        isNested = false
    }
    let type: String?
    if case .string(let value)? = error["type"] { type = value } else { type = nil }
    guard case .string(let message)? = error["message"],
          isNested || type != nil || error["code"] != nil || error["param"] != nil else {
        return nil
    }
    return (message, type, openAIStreamErrorCode(error["code"]))
}

private func openAIStreamErrorCode(_ code: JSONValue?) -> ProviderStreamError.Code? {
    switch code {
    case .string(let value): return .string(value)
    case .number(let value): return .number(value)
    default: return nil
    }
}

private func openAIStreamErrorStatus(_ code: ProviderStreamError.Code?, type: String?) -> Int {
    let numericCode: Double?
    let codeString: String?
    switch code {
    case .number(let value):
        numericCode = value
        codeString = String(value)
    case .string(let value):
        numericCode = value.utf8.count == 3 && value.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) ? Double(value) : nil
        codeString = value
    case nil:
        numericCode = nil
        codeString = nil
    }
    if let numericCode, numericCode.isFinite, numericCode.rounded() == numericCode, (400...599).contains(numericCode) {
        return Int(numericCode)
    }
    let discriminator = [codeString, type].compactMap { $0 }.joined(separator: " ").lowercased()
    if discriminator.contains("insufficient_quota") || discriminator.contains("rate_limit") { return 429 }
    if discriminator.contains("authentication") { return 401 }
    if discriminator.contains("permission") { return 403 }
    if discriminator.contains("not_found") { return 404 }
    if ["invalid", "bad_request", "context_length"].contains(where: discriminator.contains) { return 400 }
    if discriminator.contains("overload") { return 503 }
    if discriminator.contains("timeout") { return 504 }
    return 500
}
