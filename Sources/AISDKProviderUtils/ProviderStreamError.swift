import Foundation
import AISDKProvider

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
    if error is ProviderStreamError { return true }
    if case .providerStreamError? = error as? LanguageModelV4StreamError { return true }
    return false
}
