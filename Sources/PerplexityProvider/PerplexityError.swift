import AISDKProvider
import AISDKProviderUtils

public struct PerplexityErrorData: Codable, Sendable {
    public enum Code: Decodable, Sendable {
        case string(String)
        case number(Double)
        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(String.self) { self = .string(value) }
            else { self = .number(try container.decode(Double.self)) }
        }
    }
    public struct ErrorBody: Decodable, Sendable {
        public let code: Code?
        public let message: String?
        public let type: String?
        private enum Keys: String, CodingKey { case code, message, type }
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: Keys.self)
            code = container.contains(.code) ? try container.decode(Code.self, forKey: .code) : nil
            message = try container.decodeIfPresent(String.self, forKey: .message)
            type = try container.decodeIfPresent(String.self, forKey: .type)
        }
    }
    public enum ErrorValue: Decodable, Sendable {
        case string(String)
        case object(ErrorBody)
        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(String.self) { self = .string(value) }
            else { self = .object(try container.decode(ErrorBody.self)) }
        }
    }
    public enum Detail: Decodable, Sendable {
        public struct Item: Decodable, Sendable { public let msg: String }
        case string(String)
        case items([Item])
        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(String.self) { self = .string(value) }
            else { self = .items(try container.decode([Item].self)) }
        }
    }
    public let raw: JSONValue
    public let error: ErrorValue?
    public let detail: Detail?
    public let message: String?

    private enum Keys: String, CodingKey { case error, detail, message }
    public init(from decoder: Decoder) throws {
        raw = try decoder.singleValueContainer().decode(JSONValue.self)
        let container = try decoder.container(keyedBy: Keys.self)
        error = container.contains(.error) ? try container.decode(ErrorValue.self, forKey: .error) : nil
        detail = container.contains(.detail) ? try container.decode(Detail.self, forKey: .detail) : nil
        message = container.contains(.message) ? try container.decode(String.self, forKey: .message) : nil
    }
    public func encode(to encoder: Encoder) throws { try raw.encode(to: encoder) }

    var errorMessage: String {
        switch error {
        case .string(let value): return value
        case .object(let value): return value.message ?? value.type ?? "unknown error"
        case nil: break
        }
        switch detail {
        case .string(let value): return value
        case .items(let values): return values.map(\.msg).joined(separator: ", ")
        case nil: return message ?? "unknown error"
        }
    }
}

public let perplexityFailedResponseHandler: ResponseHandler<APICallError> = createJsonErrorResponseHandler(
    errorSchema: FlexibleSchema(Schema<PerplexityErrorData>.codable(PerplexityErrorData.self, jsonSchema: ["type": "object"])),
    errorToMessage: { $0.errorMessage }
)
