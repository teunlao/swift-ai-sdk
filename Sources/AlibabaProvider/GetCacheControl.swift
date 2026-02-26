import Foundation
import AISDKProvider

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/alibaba/src/get-cache-control.ts
// Upstream commit: 73d5c59
//===----------------------------------------------------------------------===//

// Alibaba allows a maximum of 4 cache breakpoints per request
private let maxCacheBreakpoints = 4

private func getCacheControlValue(
    providerMetadata: SharedV3ProviderMetadata?
) -> JSONValue? {
    let alibaba = providerMetadata?["alibaba"]
    let value = alibaba?["cacheControl"] ?? alibaba?["cache_control"]
    guard let value, value != .null else { return nil }
    return value
}

final class CacheControlValidator {
    private var breakpointCount = 0
    private var warnings: [SharedV3Warning] = []

    func getCacheControl(
        _ providerMetadata: SharedV3ProviderMetadata?
    ) -> JSONValue? {
        guard let cacheControlValue = getCacheControlValue(providerMetadata: providerMetadata) else {
            return nil
        }

        breakpointCount += 1
        if breakpointCount > maxCacheBreakpoints {
            warnings.append(.other(
                message: "Max breakpoint limit exceeded. Only the last \(maxCacheBreakpoints) cache markers will take effect."
            ))
        }

        // Pass through; provider validates the actual shape.
        return cacheControlValue
    }

    func getWarnings() -> [SharedV3Warning] {
        warnings
    }
}

