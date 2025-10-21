import Foundation

/// Shared release version used across all providers.
/// Build tooling can inject a generator via `provider` to override the default.
public enum SDKReleaseVersion {
    @usableFromInline
    nonisolated(unsafe) internal static var provider: () -> String = { "0.0.0-test" }

    /// Returns the release version string (generated value if present, otherwise the fallback).
    public static var value: String { provider() }
}
