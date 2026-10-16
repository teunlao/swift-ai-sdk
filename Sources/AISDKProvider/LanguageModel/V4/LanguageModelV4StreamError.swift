import Foundation

/**
 A mid-stream provider error payload carrying provider-owned status and retry
 metadata.

 Port of `ProviderStreamError` from
 `@ai-sdk/provider-utils/src/create-provider-stream-error.ts`. Upstream marks a
 plain payload object with a hidden symbol; in Swift the payload's type is the
 marker, and it lives here so that the `error` stream part can carry it.
 */
public struct ProviderStreamError: Error, Sendable, Equatable {
    /// Provider error code: upstream accepts a string or a number.
    public enum Code: Sendable, Equatable {
        case string(String)
        case number(Double)
    }

    public let message: String
    public let type: String?
    public let code: Code?
    public let statusCode: Int?
    public let isRetryable: Bool?
    /// The raw provider error payload.
    public let data: JSONValue

    public init(
        message: String,
        type: String? = nil,
        code: Code? = nil,
        statusCode: Int? = nil,
        isRetryable: Bool? = nil,
        data: JSONValue
    ) {
        self.message = message
        self.type = type
        self.code = code
        self.statusCode = statusCode
        self.isRetryable = isRetryable
        self.data = data
    }

    /// The payload as JSON: the metadata fields beside the raw provider `data`.
    public var jsonValue: JSONValue {
        var object: [String: JSONValue] = [
            "message": .string(message),
            "data": data,
        ]
        if let type {
            object["type"] = .string(type)
        }
        switch code {
        case .string(let value):
            object["code"] = .string(value)
        case .number(let value):
            object["code"] = .number(value)
        case nil:
            break
        }
        if let statusCode {
            object["statusCode"] = .number(Double(statusCode))
        }
        if let isRetryable {
            object["isRetryable"] = .bool(isRetryable)
        }
        return .object(object)
    }
}

/**
 Payload of the `error` stream part.

 Port of the `error: unknown` field of the upstream `error` stream part: a
 thrown error, a payload created with `createProviderStreamError`, or a raw
 provider error value.
 */
public enum LanguageModelV4StreamError: Sendable, Equatable, Codable {
    /// An error thrown while producing the stream (e.g. a chunk that failed to parse).
    case error(any Error)
    /// A provider error payload with status and retry metadata.
    case providerStreamError(ProviderStreamError)
    /// A raw provider error value.
    case value(JSONValue)

    public static func == (lhs: LanguageModelV4StreamError, rhs: LanguageModelV4StreamError) -> Bool {
        switch (lhs, rhs) {
        case (.error(let left), .error(let right)):
            return String(describing: left) == String(describing: right)
        case (.providerStreamError(let left), .providerStreamError(let right)):
            return left == right
        case (.value(let left), .value(let right)):
            return left == right
        default:
            return false
        }
    }

    /// The payload as JSON; a thrown error becomes its description.
    public var jsonValue: JSONValue {
        switch self {
        case .error(let error):
            if let localized = error as? LocalizedError, let description = localized.errorDescription {
                return .string(description)
            }
            return .string(String(describing: error))
        case .providerStreamError(let payload):
            return payload.jsonValue
        case .value(let value):
            return value
        }
    }

    public init(from decoder: Decoder) throws {
        self = .value(try JSONValue(from: decoder))
    }

    public func encode(to encoder: Encoder) throws {
        try jsonValue.encode(to: encoder)
    }
}
