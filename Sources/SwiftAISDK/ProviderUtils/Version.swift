// Version string for the Swift AI SDK package.
// This should be kept in sync with Package.swift.
//
// Upstream reference: packages/provider-utils/src/version.ts
// In TypeScript, this is injected at build time via __PACKAGE_VERSION__.
// In Swift, we hardcode it here for simplicity.

/// The current version of the SwiftAISDK package.
/// Used in User-Agent headers and telemetry.
public let VERSION: String = "0.1.0-alpha"
