import Foundation
import AISDKProvider

/**
 A mid-stream provider error payload carrying provider-owned status and retry
 metadata, without requiring provider targets to depend on the `ai` layer.

 Port of `ProviderStreamError` from `@ai-sdk/provider-utils/src/create-provider-stream-error.ts`.
 Upstream marks the plain payload object with a hidden symbol; in Swift the
 payload's type is the marker.
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

    /**
     The payload as carried by a V4 `error` stream part, whose Swift payload is
     JSON: the metadata fields beside the raw provider `data`.
     */
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

/// Port of `createProviderStreamError` from `@ai-sdk/provider-utils/src/create-provider-stream-error.ts`.
public func createProviderStreamError(
    message: String,
    type: String? = nil,
    code: ProviderStreamError.Code? = nil,
    statusCode: Int? = nil,
    isRetryable: Bool? = nil,
    data: JSONValue
) -> ProviderStreamError {
    ProviderStreamError(
        message: message,
        type: type,
        code: code,
        statusCode: statusCode,
        isRetryable: isRetryable,
        data: data
    )
}

/// Whether `error` is a payload created by `createProviderStreamError`.
public func isProviderStreamError(_ error: Any?) -> Bool {
    error is ProviderStreamError
}
