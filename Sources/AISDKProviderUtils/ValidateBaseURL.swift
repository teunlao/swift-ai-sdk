import Foundation
import AISDKProvider

public func validateBaseURL(_ baseURL: String?) throws -> String? {
    if baseURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
        throw InvalidArgumentError(
            argument: "baseURL",
            message: "baseURL must be a non-empty string."
        )
    }
    return baseURL
}
