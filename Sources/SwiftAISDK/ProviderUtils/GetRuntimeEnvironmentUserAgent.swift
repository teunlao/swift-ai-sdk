import Foundation

/**
 Returns the runtime environment user agent string.
 Port of `@ai-sdk/provider-utils/src/get-runtime-environment-user-agent.ts`

 Swift adaptation: returns platform-specific runtime identifier.
 */
public func getRuntimeEnvironmentUserAgent() -> String {
    #if os(iOS)
    return "runtime/swift-ios"
    #elseif os(macOS)
    return "runtime/swift-macos"
    #elseif os(watchOS)
    return "runtime/swift-watchos"
    #elseif os(tvOS)
    return "runtime/swift-tvos"
    #elseif os(Linux)
    return "runtime/swift-linux"
    #else
    return "runtime/swift"
    #endif
}
