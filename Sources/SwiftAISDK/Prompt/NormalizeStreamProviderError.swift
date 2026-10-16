import Foundation
import AISDKProvider
import AISDKProviderUtils

/// A provider error value that is not a well-formed provider error payload.
public struct StreamErrorValue: Error, LocalizedError, CustomStringConvertible, Sendable {
    public let value: JSONValue

    public init(value: JSONValue) {
        self.value = value
    }

    public var description: String {
        if case .string(let text) = value { return text }
        return value.jsonString
    }

    public var errorDescription: String? { description }
}

/**
 Normalizes the payload of an `error` stream part into an error.

 Port of `@ai-sdk/ai/src/prompt/normalize-stream-provider-error.ts`: provider
 stream error payloads and well-formed provider error objects become a
 `StreamProviderError` with status and retry metadata; thrown errors stay as
 they are; other values are wrapped unchanged in `StreamErrorValue`.
 */
public func normalizeStreamProviderError(_ payload: LanguageModelV4StreamError) -> any Error {
    switch payload {
    case .error(let error):
        return error

    case .providerStreamError(let providerError):
        let payload = providerError.jsonValue.objectEntries ?? [:]
        return makeStreamProviderError(details: payload, outer: payload, data: providerError.data)
            ?? StreamErrorValue(value: providerError.jsonValue)

    case .value(let value):
        guard let outer = value.objectEntries else {
            return StreamErrorValue(value: value)
        }
        let details = outer["response"]?.objectEntries?["error"]?.objectEntries
            ?? outer["error"]?.objectEntries
            ?? outer
        return makeStreamProviderError(details: details, outer: outer, data: value)
            ?? StreamErrorValue(value: value)
    }
}

private func makeStreamProviderError(
    details: [String: JSONValue],
    outer: [String: JSONValue],
    data: JSONValue
) -> StreamProviderError? {
    guard case .string(let message)? = details["message"] else {
        return nil
    }

    let type = details["type"]?.stringValue ?? outer["type"]?.stringValue
    let code = codeValue(details["code"]) ?? codeValue(outer["code"])
    let explicitStatusCode = [
        details["statusCode"], outer["statusCode"],
        details["status_code"], outer["status_code"],
        details["status"], outer["status"],
        details["code"], outer["code"],
    ].lazy.compactMap(httpStatusCode).first
    let messageMetadata = inferExactMessageMetadata(message)
    let statusCode = explicitStatusCode ?? messageMetadata?.statusCode
    let explicitRetryability = [
        details["isRetryable"], outer["isRetryable"],
        details["is_retryable"], outer["is_retryable"],
    ].lazy.compactMap { value -> Bool? in
        if case .bool(let flag)? = value { return flag }
        return nil
    }.first

    return StreamProviderError(
        message: message,
        type: type,
        code: code,
        statusCode: statusCode,
        isRetryable: explicitRetryability
            ?? messageMetadata?.isRetryable
            ?? isRetryableStreamStatusCode(statusCode),
        data: data
    )
}

private func inferExactMessageMetadata(_ message: String) -> (statusCode: Int, isRetryable: Bool)? {
    switch message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "overloaded", "overloaded error", "model overloaded":
        return (503, true)
    case "internal server error":
        return (500, true)
    case "service unavailable":
        return (503, true)
    default:
        return nil
    }
}

private func codeValue(_ value: JSONValue?) -> ProviderStreamError.Code? {
    switch value {
    case .string(let text)?: return .string(text)
    case .number(let number)?: return .number(number)
    default: return nil
    }
}

private func httpStatusCode(_ value: JSONValue?) -> Int? {
    let number: Double
    switch value {
    case .string(let text)?:
        guard text.count == 3, let parsed = Int(text), text.allSatisfy(\.isNumber) else { return nil }
        number = Double(parsed)
    case .number(let parsed)?:
        number = parsed
    default:
        return nil
    }
    guard number.rounded() == number, number >= 400, number <= 599 else { return nil }
    return Int(number)
}

private extension JSONValue {
    var objectEntries: [String: JSONValue]? {
        if case .object(let object) = self { return object }
        return nil
    }

    var stringValue: String? {
        if case .string(let text) = self { return text }
        return nil
    }
}
