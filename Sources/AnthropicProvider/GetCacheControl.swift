import Foundation
import AISDKProvider
import AISDKProviderUtils

public func getAnthropicCacheControl(from metadata: SharedV3ProviderMetadata?) -> AnthropicCacheControl? {
    guard let anthropic = metadata?["anthropic"] else { return nil }
    let value = anthropic["cacheControl"] ?? anthropic["cache_control"]
    guard case .object(let object) = value else { return nil }

    var type: String? = nil
    var ttl: AnthropicCacheControl.TTL? = nil
    var additional: [String: JSONValue] = [:]

    for (key, entry) in object {
        switch key {
        case "type":
            if case .string(let typeString) = entry {
                type = typeString
            } else {
                additional[key] = entry
            }
        case "ttl":
            if case .string(let ttlString) = entry, let parsed = AnthropicCacheControl.TTL(rawValue: ttlString) {
                ttl = parsed
            } else {
                additional[key] = entry
            }
        default:
            additional[key] = entry
        }
    }

    return AnthropicCacheControl(type: type, ttl: ttl, additionalFields: additional)
}

// MARK: - Cache Control Validation

/// Anthropic allows a maximum of 4 cache breakpoints per request.
private let _maxAnthropicCacheBreakpoints = 4

public struct CacheControlContext: Sendable {
    public let type: String
    public let canCache: Bool

    public init(type: String, canCache: Bool) {
        self.type = type
        self.canCache = canCache
    }
}

/// Stateful validator that tracks cache breakpoints and produces warnings.
///
/// Port of `CacheControlValidator` from `@ai-sdk/anthropic/src/get-cache-control.ts`.
public final class CacheControlValidator: @unchecked Sendable {
    private var breakpointCount: Int = 0
    private var warnings: [SharedV3Warning] = []

    public init() {}

    public func getCacheControl(
        _ providerMetadata: SharedV3ProviderMetadata?,
        context: CacheControlContext
    ) -> AnthropicCacheControl? {
        guard let cacheControlValue = getAnthropicCacheControl(from: providerMetadata) else {
            return nil
        }

        if context.canCache == false {
            warnings.append(.unsupported(
                feature: "cache_control on non-cacheable context",
                details: "cache_control cannot be set on \(context.type). It will be ignored."
            ))
            return nil
        }

        breakpointCount += 1
        if breakpointCount > _maxAnthropicCacheBreakpoints {
            warnings.append(.unsupported(
                feature: "cacheControl breakpoint limit",
                details: "Maximum \(_maxAnthropicCacheBreakpoints) cache breakpoints exceeded (found \(breakpointCount)). This breakpoint will be ignored."
            ))
            return nil
        }

        return cacheControlValue
    }

    public func getWarnings() -> [SharedV3Warning] {
        warnings
    }
}
