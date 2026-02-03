/**
 Deeply merges provider options dictionaries.

 Port of the providerOptions merge behavior in:
 - `@ai-sdk/ai/src/generate-text/generate-text.ts`
 - `@ai-sdk/ai/src/generate-text/stream-text.ts`

 Upstream uses `mergeObjects` (deep merge) for providerOptions.
 In Swift, providerOptions are represented as `[String: [String: JSONValue]]`, so we perform
 a deep merge on nested `.object` JSON values.
 */

import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Deeply merges provider options.

 - Parameters:
   - base: Base provider options (outer dictionary keyed by provider).
   - overrides: Per-step overrides to merge on top of `base`.
 - Returns: Merged provider options, or nil when both inputs are nil.
 */
public func mergeProviderOptions(
    _ base: ProviderOptions?,
    _ overrides: ProviderOptions?
) -> ProviderOptions? {
    if base == nil && overrides == nil { return nil }
    if base == nil { return overrides }
    if overrides == nil { return base }

    var result = base ?? [:]

    for (provider, overrideOptions) in overrides ?? [:] {
        let baseOptions = result[provider] ?? [:]
        result[provider] = mergeJSONObject(baseOptions, overrideOptions)
    }

    return result
}

private func mergeJSONObject(
    _ base: [String: JSONValue],
    _ overrides: [String: JSONValue]
) -> [String: JSONValue] {
    var result = base

    for (key, overrideValue) in overrides {
        if case .object(let overrideObject) = overrideValue,
           case .object(let baseObject)? = result[key] {
            result[key] = .object(mergeJSONObject(baseObject, overrideObject))
        } else {
            result[key] = overrideValue
        }
    }

    return result
}

