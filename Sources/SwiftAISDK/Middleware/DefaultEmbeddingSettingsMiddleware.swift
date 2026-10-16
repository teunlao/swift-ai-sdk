import AISDKProvider

/// Default settings that can be applied to embedding model calls.
public struct DefaultEmbeddingSettings: Sendable {
    public let headers: SharedV4Headers?
    public let providerOptions: SharedV4ProviderOptions?

    public init(
        headers: SharedV4Headers? = nil,
        providerOptions: SharedV4ProviderOptions? = nil
    ) {
        self.headers = headers
        self.providerOptions = providerOptions
    }
}

/**
 Applies default settings for an embedding model.

 Port of `@ai-sdk/ai/src/middleware/default-embedding-settings-middleware.ts`:
 call headers and provider options deep-merge over the defaults, the call winning.
 */
public func defaultEmbeddingSettingsMiddleware(
    settings: DefaultEmbeddingSettings
) -> EmbeddingModelV4Middleware {
    EmbeddingModelV4Middleware(
        transformParams: { params, _ in
            EmbeddingModelV4CallOptions(
                values: params.values,
                dimensions: params.dimensions,
                abortSignal: params.abortSignal,
                providerOptions: mergeProviderOptions(settings.providerOptions, params.providerOptions),
                headers: mergeSettingHeaders(settings.headers, params.headers)
            )
        }
    )
}
