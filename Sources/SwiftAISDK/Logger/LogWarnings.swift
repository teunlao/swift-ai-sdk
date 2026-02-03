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

/// Thread-safe wrapper for first warning state using NSLock
private final class FirstWarningState: @unchecked Sendable {
    private var hasLogged = false
    private let lock = NSLock()

    func checkAndSet() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        if !hasLogged {
            hasLogged = true
            return true
        }
        return false
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        hasLogged = false
    }
}

/// Global lock for synchronizing access to all mutable state
private let globalWarningsLock = NSLock()

/// Storage for warning observers - protected by globalWarningsLock.
/// We treat the public property as a replaceable single-observer API:
/// assigning a non-nil closure replaces the current list with that closure;
/// assigning nil clears all observers. Internally we keep an array so we can
/// evolve to multiple observers if needed without changing call sites.
// Observer stack: setting a non-nil observer pushes it; setting nil pops the most-recent one.
// This matches common test patterns that set the hook in `setUp` and clear in `tearDown`,
// while allowing overlapping tests to coexist without clobbering each other.
private nonisolated(unsafe) var _logWarningsObservers: [(@Sendable ([Warning]) -> Void)] = []

/// Storage for logger config - protected by globalWarningsLock
private nonisolated(unsafe) var _AI_SDK_LOG_WARNINGS: Any? = nil
private nonisolated(unsafe) var _warningsLoggingDisabledForProcess: Bool = false

/// Union type for all warning types
public enum Warning: Sendable, Equatable {
    case languageModel(SharedV3Warning)
    case imageModel(SharedV3Warning)
    case speechModel(SharedV3Warning)
    case transcriptionModel(SharedV3Warning)
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
/// **Thread Safety**: Protected by NSLock for safe concurrent access
nonisolated(unsafe) public var AI_SDK_LOG_WARNINGS: Any? {
    get {
        globalWarningsLock.lock()
        defer { globalWarningsLock.unlock() }
        return _AI_SDK_LOG_WARNINGS
    }
    set {
        globalWarningsLock.lock()
        defer { globalWarningsLock.unlock() }
        _AI_SDK_LOG_WARNINGS = newValue
    }
}

/// Information message displayed on first warning
public let FIRST_WARNING_INFO_MESSAGE =
    "AI SDK Warning System: To turn off warning logging, set the AI_SDK_LOG_WARNINGS global to false."

/// Testing hook to observe raw warning arrays before internal processing.
/// Thread-safe via lock-protected storage
nonisolated(unsafe) var logWarningsObserver: (@Sendable ([Warning]) -> Void)? {
    get {
        globalWarningsLock.lock(); defer { globalWarningsLock.unlock() }
        return _logWarningsObservers.last
    }
    set {
        globalWarningsLock.lock(); defer { globalWarningsLock.unlock() }
        if let observer = newValue {
            _logWarningsObservers.append(observer)
        } else {
            if !_logWarningsObservers.isEmpty {
                _logWarningsObservers.removeLast()
            }
        }
    }
}

/// Thread-safe state for tracking first warning
private let firstWarningState = FirstWarningState()

/// Format a warning into a human-readable string
private func formatWarning(_ warning: Warning) -> String {
    let prefix = "AI SDK Warning:"

    switch warning {
    case .languageModel(let w):
        return formatSharedV3Warning(w, prefix: prefix)
    case .imageModel(let w):
        return formatSharedV3Warning(w, prefix: prefix)
    case .speechModel(let w):
        return formatSharedV3Warning(w, prefix: prefix)
    case .transcriptionModel(let w):
        return formatSharedV3Warning(w, prefix: prefix)
    }
}

/// Format SharedV3Warning
private func formatSharedV3Warning(_ warning: SharedV3Warning, prefix: String) -> String {
    switch warning {
    case .unsupported(let feature, let details):
        var message = "\(prefix) The feature \"\(feature)\" is not supported"
        if let details = details {
            message += " - \(details)"
        }
        return message

    case .compatibility(let feature, let details):
        var message = "\(prefix) Using compatibility mode for \"\(feature)\""
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
    // Snapshot observers (thread-safe) and notify
    let observers: [(@Sendable ([Warning]) -> Void)] = {
        globalWarningsLock.lock(); defer { globalWarningsLock.unlock() }
        return _logWarningsObservers
    }()
    for obs in observers { obs(warnings) }

    // If empty, do nothing
    guard !warnings.isEmpty else {
        return
    }

    // Thread-safe access to disable flag and logger configuration
    let logger: Any?
    let loggingDisabled: Bool
    globalWarningsLock.lock()
    loggingDisabled = _warningsLoggingDisabledForProcess
    logger = _AI_SDK_LOG_WARNINGS
    globalWarningsLock.unlock()

    if loggingDisabled {
        return
    }

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

    // Display information note on first call (thread-safe with NSLock)
    let shouldPrintInfo = firstWarningState.checkAndSet()

    if shouldPrintInfo {
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
    firstWarningState.reset()
}

public func setWarningsLoggingDisabledForTests(_ disabled: Bool) {
    globalWarningsLock.lock()
    _warningsLoggingDisabledForProcess = disabled
    globalWarningsLock.unlock()
}
