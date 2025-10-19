import Foundation
import AISDKProvider
import AISDKProviderUtils

public func getAnthropicCacheControl(from metadata: SharedV3ProviderMetadata?) -> AnthropicCacheControl? {
    guard let anthropic = metadata?["anthropic"] else { return nil }
    let value = anthropic["cacheControl"] ?? anthropic["cache_control"]
    guard case .object(let object) = value else { return nil }

    let type: String
    if case .string(let typeString) = object["type"] {
        type = typeString
    } else {
        type = "ephemeral"
    }

    var ttl: AnthropicCacheControl.TTL?
    if case .string(let ttlString)? = object["ttl"], let parsed = AnthropicCacheControl.TTL(rawValue: ttlString) {
        ttl = parsed
    }

    return AnthropicCacheControl(type: type, ttl: ttl)
}
