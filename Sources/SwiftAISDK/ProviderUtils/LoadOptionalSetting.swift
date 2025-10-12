import Foundation

/**
 Loads an optional string setting from a parameter or environment variable.
 Port of `@ai-sdk/provider-utils/src/load-optional-setting.ts`
 */
public func loadOptionalSetting(
    settingValue: String?,
    environmentVariableName: String
) -> String? {
    if let settingValue = settingValue {
        return settingValue
    }

    return ProcessInfo.processInfo.environment[environmentVariableName]
}
