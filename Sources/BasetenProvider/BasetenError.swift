import Foundation
import AISDKProvider
import AISDKProviderUtils
import OpenAICompatibleProvider

public struct BasetenErrorData: Codable, Sendable, Equatable {
    public struct Detail: Codable, Sendable, Equatable {
        public let message: String
        public let object: String?
        public let type: String?
        public let param: JSONValue?
        public let code: OpenAICompatibleErrorCode?
    }
    public enum Payload: Codable, Sendable, Equatable {
        case text(String)
        case details(Detail)
        public var message: String {
            switch self { case .text(let value): return value; case .details(let value): return value.message }
        }
        public init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let text = try? c.decode(String.self) { self = .text(text) }
            else { self = .details(try c.decode(Detail.self)) }
        }
        public func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer()
            switch self { case .text(let value): try c.encode(value); case .details(let value): try c.encode(value) }
        }
    }
    public let error: Payload
}
private let basetenErrorSchema = FlexibleSchema(Schema<BasetenErrorData>.codable(BasetenErrorData.self, jsonSchema: ["type": "object"]))
private struct BasetenErrorExtractionFailure: Error {}
public let basetenErrorConfiguration = OpenAICompatibleErrorConfiguration(
    errorSchema: basetenErrorSchema, errorToMessage: { $0.error.message }, extractMessage: { value in
        guard case .object(let object) = value, let error = object["error"] else { throw BasetenErrorExtractionFailure() }
        if case .string(let message) = error { return message }
        if case .object(let error) = error, case .string(let message) = error["message"] { return message }
        throw BasetenErrorExtractionFailure()
    }
)
