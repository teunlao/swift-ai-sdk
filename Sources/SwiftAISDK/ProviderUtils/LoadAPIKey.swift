import Foundation

/**
 Loads an API key from a parameter or environment variable.
 Port of `@ai-sdk/provider-utils/src/load-api-key.ts`
 */
public func loadAPIKey(
    apiKey: String?,
    environmentVariableName: String,
    apiKeyParameterName: String = "apiKey",
    description: String
) throws -> String {
    if let apiKey = apiKey {
        return apiKey
    }

    guard let envValue = ProcessInfo.processInfo.environment[environmentVariableName] else {
        throw LoadAPIKeyError(
            message: "\(description) API key is missing. " +
                    "Pass it using the '\(apiKeyParameterName)' parameter " +
                    "or the \(environmentVariableName) environment variable."
        )
    }

    return envValue
}
