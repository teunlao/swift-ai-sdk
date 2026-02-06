import Foundation

/// Port of `@ai-sdk/ai/src/util/merge-abort-signals.ts`.
///
/// Swift adapts AbortSignals as `@Sendable () -> Bool`.
func mergeAbortSignals(
    _ signals: (@Sendable () -> Bool)?...
) -> (@Sendable () -> Bool)? {
    let validSignals = signals.compactMap { $0 }
    guard !validSignals.isEmpty else { return nil }
    if validSignals.count == 1 { return validSignals[0] }

    return {
        for signal in validSignals {
            if signal() { return true }
        }
        return false
    }
}

