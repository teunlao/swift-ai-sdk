/**
 SDK version information.

 Port of `@ai-sdk/ai/src/version.ts`.
 */

import Foundation
import AISDKProviderUtils

/// SDK version string (set at build time, defaults to development version)
public let VERSION = SDKReleaseVersion.value
