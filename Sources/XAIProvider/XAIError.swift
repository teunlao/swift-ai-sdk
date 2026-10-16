import Foundation
import AISDKProvider
import AISDKProviderUtils

public enum XAIErrorData: Sendable, Equatable, Codable {
    public struct ErrorBody: Sendable, Equatable, Codable {
        public let message: String
        public let type: String?
        public let param: JSONValue?
        public let code: JSONValue?
    }
    case api(error: ErrorBody)
    case responses(code: String, error: String)
    case speech(error: String)

    private enum CodingKeys: String, CodingKey { case error, code }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let error = try? container.decode(ErrorBody.self, forKey: .error) {
            if let code = error.code, code != .null {
                switch code {
                case .string, .number: break
                default: throw DecodingError.dataCorruptedError(forKey: .error, in: container, debugDescription: "Invalid error code")
                }
            }
            self = .api(error: error)
        } else {
            let message = try container.decode(String.self, forKey: .error)
            if let code = try? container.decode(String.self, forKey: .code) { self = .responses(code: code, error: message) }
            else { self = .speech(error: message) }
        }
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .api(let error): try container.encode(error, forKey: .error)
        case .responses(let code, let error):
            try container.encode(code, forKey: .code)
            try container.encode(error, forKey: .error)
        case .speech(let error): try container.encode(error, forKey: .error)
        }
    }
    var message: String {
        switch self {
        case .api(let error): error.message
        case .responses(let code, let error): "\(code): \(error)"
        case .speech(let error): error
        }
    }
}

public let xaiErrorDataSchema = FlexibleSchema(Schema<XAIErrorData>.codable(XAIErrorData.self, jsonSchema: .object(["type": .string("object")])))
public let xaiFailedResponseHandler = createJsonErrorResponseHandler(errorSchema: xaiErrorDataSchema, errorToMessage: { $0.message })
