import Foundation
import AISDKProvider

/**
 Checks whether a value is a provider reference mapping provider names to
 provider-specific identifiers.

 Swift adaptation of `@ai-sdk/provider-utils/src/is-provider-reference.ts`.
 */
public func isProviderReference(_ data: Any) -> Bool {
    if data is Data || data is URL || data is NSNull {
        return false
    }

    if let reference = data as? SharedV4ProviderReference {
        return reference["type"] == nil
    }

    if let object = data as? [String: Any] {
        return object["type"] == nil && object.values.allSatisfy { $0 is String }
    }

    if case .object(let object) = data as? JSONValue {
        return object["type"] == nil && object.values.allSatisfy {
            if case .string = $0 {
                return true
            }
            return false
        }
    }

    return false
}

/**
 Resolves a provider reference to the provider-specific identifier for the given
 provider.

 Swift port of `@ai-sdk/provider-utils/src/resolve-provider-reference.ts`.
 */
public func resolveProviderReference(
    reference: SharedV4ProviderReference,
    provider: String
) throws -> String {
    if let id = reference[provider] {
        return id
    }

    throw NoSuchProviderReferenceError(
        provider: provider,
        reference: reference
    )
}
