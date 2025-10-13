import Foundation

/**
 Returns current timestamp in milliseconds.

 Port of `@ai-sdk/ai/src/util/now.ts`.

 Uses high-precision system uptime when available, otherwise falls back to Date-based time.
 */
public func now() -> Double {
    #if os(Linux) || os(Windows)
    // Linux/Windows: use Date.now (milliseconds since epoch)
    return Date().timeIntervalSince1970 * 1000
    #else
    // macOS/iOS: use ProcessInfo.systemUptime (high precision)
    return ProcessInfo.processInfo.systemUptime * 1000
    #endif
}
