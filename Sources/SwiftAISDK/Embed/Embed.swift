import Foundation
import AISDKProvider
import AISDKProviderUtils

/// Callback for embedding operation lifecycle events.
public typealias EmbedCallback<Event: Sendable> = @Sendable (Event) async throws -> Void

/**
 Embed a single value using an embedding model.

 Port of `@ai-sdk/ai/src/embed/embed.ts`.
 */
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func embed(
    model modelArg: any EmbeddingModelConvertible,
    value: String,
    dimensions: Int? = nil,
    providerOptions: ProviderOptions? = nil,
    maxRetries: Int? = nil,
    abortSignal: (@Sendable () -> Bool)? = nil,
    headers: [String: String]? = nil,
    telemetry: TelemetryOptions? = nil,
    runtimeContext: Context = [:],
    onStart: EmbedCallback<EmbedStartEvent<String>>? = nil,
    onEnd: EmbedCallback<EmbedEndEvent<String, Embedding>>? = nil
) async throws -> DefaultEmbedResult<String> {
    try validateEmbeddingDimensions(dimensions)
    let model = try resolveEmbeddingModel(modelArg)

    let preparedRetries = try prepareRetries(
        maxRetries: maxRetries,
        abortSignal: abortSignal
    )

    let headersWithUserAgent = withUserAgentSuffix(
        headers ?? [:],
        "ai/\(VERSION)"
    )

    let generateCallId = try createIDGenerator(prefix: "call", size: 24)
    let callId = generateCallId()
    let dispatcher = TelemetryDispatcher(telemetry: telemetry)

    let startEvent = EmbedStartEvent(
        runtimeContext: runtimeContext, callId: callId, operationId: "ai.embed",
        provider: model.provider, modelId: model.modelId, value: value,
        dimensions: dimensions, maxRetries: preparedRetries.maxRetries,
        headers: headersWithUserAgent, providerOptions: providerOptions
    )
    await notify(
        invoke(onStart, with: startEvent),
        { await dispatcher.onStart(.embed(startEvent)) }
    )

    do {
        let (embedding, usage, warnings, providerMetadata, providerResponse) = try await preparedRetries.retry.call {
            let embedCallId = generateCallId()
            await dispatcher.onEmbedStart(EmbeddingModelCallStartEvent(
                callId: callId, embedCallId: embedCallId, operationId: "ai.embed.doEmbed",
                provider: model.provider, modelId: model.modelId, values: [value], dimensions: dimensions
            ))

            let modelResponse = try await model.doEmbed(
                options: EmbeddingModelV4CallOptions(
                    values: [value],
                    dimensions: dimensions,
                    abortSignal: abortSignal,
                    providerOptions: providerOptions,
                    headers: headersWithUserAgent
                )
            )
            let usage = makeEmbeddingUsage(from: modelResponse.usage)

            await dispatcher.onEmbedEnd(EmbeddingModelCallEndEvent(
                callId: callId, embedCallId: embedCallId, operationId: "ai.embed.doEmbed",
                provider: model.provider, modelId: model.modelId, values: [value],
                embeddings: modelResponse.embeddings, usage: usage
            ))

            guard let embedding = modelResponse.embeddings.first else {
                throw InvalidResponseDataError(
                    data: modelResponse.embeddings,
                    message: "No embedding generated."
                )
            }

            return (
                embedding,
                usage,
                modelResponse.warnings,
                modelResponse.providerMetadata,
                modelResponse.response
            )
        }

        logWarnings(warnings.map { .embeddingModel($0) })

        let endEvent = EmbedEndEvent(
            runtimeContext: runtimeContext, callId: callId, operationId: "ai.embed",
            provider: model.provider, modelId: model.modelId, value: value,
            embedding: embedding, usage: usage, warnings: warnings,
            providerMetadata: providerMetadata, response: .single(providerResponse)
        )
        await notify(
            invoke(onEnd, with: endEvent),
            { await dispatcher.onEnd(.embed(endEvent)) }
        )

        return DefaultEmbedResult(
            value: value,
            embedding: embedding,
            usage: usage,
            warnings: warnings,
            providerMetadata: providerMetadata,
            response: providerResponse
        )
    } catch {
        await dispatcher.onError(callId: callId, error: error)
        throw error
    }
}

