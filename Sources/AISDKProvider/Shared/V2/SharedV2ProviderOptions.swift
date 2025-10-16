import Foundation

/**
 Additional provider-specific options supplied from the AI SDK to the provider.
 The outer dictionary is keyed by provider name; inner dictionaries are keyed by provider-specific option keys.

 Port of `@ai-sdk/provider/src/shared/v2/shared-v2-provider-options.ts`.
 */
public typealias SharedV2ProviderOptions = [String: [String: JSONValue]]
