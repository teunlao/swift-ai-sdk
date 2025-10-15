// Version string for the AISDKProviderUtils package.
// This should be kept in sync with Package.swift.
//
// Upstream reference: packages/provider-utils/src/version.ts
// In TypeScript, this is injected at build time via __PACKAGE_VERSION__.
// In Swift, we hardcode it here for simplicity.

/// The current version of the AISDKProviderUtils package.
/// Used in User-Agent headers and telemetry.
internal let PROVIDER_UTILS_VERSION: String = "0.1.0-alpha"
