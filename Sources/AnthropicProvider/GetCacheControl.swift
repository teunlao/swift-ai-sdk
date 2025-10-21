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
