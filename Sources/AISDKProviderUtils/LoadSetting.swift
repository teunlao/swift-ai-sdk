import Foundation
import AISDKProvider

/**
 Loads a string setting from a parameter or environment variable.
 Port of `@ai-sdk/provider-utils/src/load-setting.ts`
 */
public func loadSetting(
    settingValue: String?,
    environmentVariableName: String,
    settingName: String,
    description: String
) throws -> String {
    if let settingValue = settingValue {
        return settingValue
    }

    guard let envValue = ProcessInfo.processInfo.environment[environmentVariableName] else {
        throw LoadSettingError(
            message: "\(description) setting is missing. " +
                    "Pass it using the '\(settingName)' parameter " +
                    "or the \(environmentVariableName) environment variable."
        )
    }

    return envValue
}
