/**
 Warning logger for AI SDK.

 Port of `@ai-sdk/ai/src/logger/log-warnings.ts`.

 Provides centralized warning logging with:
 - Global configuration via AI_SDK_LOG_WARNINGS
 - Custom logger support
 - Formatted warning messages
 - First-call information note
 */

import Foundation
import AISDKProvider
import AISDKProviderUtils

/// Union type for all warning types
public enum Warning: Sendable, Equatable {
    case languageModel(LanguageModelV3CallWarning)
    case imageModel(ImageModelV3CallWarning)
    case speechModel(SpeechModelV3CallWarning)
    case transcriptionModel(TranscriptionModelV3CallWarning)
}

/// Custom logger function type
public typealias LogWarningsFunction = @Sendable ([Warning]) -> Void

/// Global warning logger configuration
///
/// Can be:
/// - `false` to disable all warning logging
/// - Custom `LogWarningsFunction` for custom handling
/// - `nil` or other values for default console logging
///
/// **Thread Safety**: Marked `nonisolated(unsafe)` to match JavaScript's
/// global mutable state. Users are responsible for synchronization if
/// mutating from multiple threads.
nonisolated(unsafe) public var AI_SDK_LOG_WARNINGS: Any? = nil

/// Information message displayed on first warning
public let FIRST_WARNING_INFO_MESSAGE =
    "AI SDK Warning System: To turn off warning logging, set the AI_SDK_LOG_WARNINGS global to false."

/// Track if we've logged before (for first-time info message)
///
/// **Thread Safety**: Marked `nonisolated(unsafe)` to match JavaScript's
/// module-level mutable state. Users are responsible for synchronization.
nonisolated(unsafe) private var hasLoggedBefore = false

/// Format a warning into a human-readable string
private func formatWarning(_ warning: Warning) -> String {
    let prefix = "AI SDK Warning:"

    switch warning {
    case .languageModel(let w):
        return formatLanguageModelWarning(w, prefix: prefix)
    case .imageModel(let w):
        return formatImageModelWarning(w, prefix: prefix)
    case .speechModel(let w):
        return formatSpeechModelWarning(w, prefix: prefix)
    case .transcriptionModel(let w):
        return formatTranscriptionModelWarning(w, prefix: prefix)
    }
}

/// Format LanguageModelV3CallWarning
private func formatLanguageModelWarning(_ warning: LanguageModelV3CallWarning, prefix: String) -> String {
    switch warning {
    case .unsupportedSetting(let setting, let details):
        var message = "\(prefix) The \"\(setting)\" setting is not supported by this model"
        if let details = details {
            message += " - \(details)"
        }
        return message

    case .unsupportedTool(let tool, let details):
        let toolName: String
        switch tool {
        case .function(let functionTool):
            toolName = functionTool.name
        case .providerDefined:
            toolName = "unknown tool"
        }

        var message = "\(prefix) The tool \"\(toolName)\" is not supported by this model"
        if let details = details {
            message += " - \(details)"
        }
        return message

    case .other(let message):
        return "\(prefix) \(message)"
    }
}

/// Format ImageModelV3CallWarning
private func formatImageModelWarning(_ warning: ImageModelV3CallWarning, prefix: String) -> String {
    switch warning {
    case .unsupportedSetting(let setting, let details):
        var message = "\(prefix) The \"\(setting)\" setting is not supported by this model"
        if let details = details {
            message += " - \(details)"
        }
        return message

    case .other(let message):
        return "\(prefix) \(message)"
    }
}

/// Format SpeechModelV3CallWarning
private func formatSpeechModelWarning(_ warning: SpeechModelV3CallWarning, prefix: String) -> String {
    switch warning {
    case .unsupportedSetting(let setting, let details):
        var message = "\(prefix) The \"\(setting)\" setting is not supported by this model"
        if let details = details {
            message += " - \(details)"
        }
        return message

    case .other(let message):
        return "\(prefix) \(message)"
    }
}

/// Format TranscriptionModelV3CallWarning
private func formatTranscriptionModelWarning(_ warning: TranscriptionModelV3CallWarning, prefix: String) -> String {
    switch warning {
    case .unsupportedSetting(let setting, let details):
        var message = "\(prefix) The \"\(setting)\" setting is not supported by this model"
        if let details = details {
            message += " - \(details)"
        }
        return message

    case .other(let message):
        return "\(prefix) \(message)"
    }
}

/// Log warnings with configurable behavior
///
/// Behavior depends on `AI_SDK_LOG_WARNINGS`:
/// - `false`: No logging
/// - Custom function: Calls custom function with warnings
/// - Default (nil/other): Logs to console with formatted messages
///
/// - Parameter warnings: Array of warnings to log
public func logWarnings(_ warnings: [Warning]) {
    // If empty, do nothing
    guard !warnings.isEmpty else {
        return
    }

    let logger = AI_SDK_LOG_WARNINGS

    // If explicitly disabled
    if let loggerBool = logger as? Bool, loggerBool == false {
        return
    }

    // If custom logger function provided
    if let loggerFunc = logger as? LogWarningsFunction {
        loggerFunc(warnings)
        return
    }

    // Default behavior: log to console

    // Display information note on first call
    if !hasLoggedBefore {
        hasLoggedBefore = true
        print(FIRST_WARNING_INFO_MESSAGE)
    }

    // Log each warning
    for warning in warnings {
        print(formatWarning(warning))
    }
}

/// Reset log warnings state (for testing)
///
/// Resets the `hasLoggedBefore` flag to allow testing
/// first-call behavior multiple times.
public func resetLogWarningsState() {
    hasLoggedBefore = false
}
