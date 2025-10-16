import Foundation

/**
 Additional provider-specific metadata passed through from the AI SDK to the provider.
 The outer dictionary is keyed by provider name; inner dictionaries are keyed by provider-specific metadata keys.

 Port of `@ai-sdk/provider/src/shared/v2/shared-v2-provider-metadata.ts`.
 */
public typealias SharedV2ProviderMetadata = [String: [String: JSONValue]]
