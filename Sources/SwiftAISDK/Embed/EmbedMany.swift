import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Embed multiple values using an embedding model.

 Port of `@ai-sdk/ai/src/embed/embed-many.ts`.
 */
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func embedMany(
    model modelArg: EmbeddingModel,
    values: [String],
    dimensions: Int? = nil,
    maxParallelCalls: Int? = nil,
    maxRetries: Int? = nil,
    abortSignal: (@Sendable () -> Bool)? = nil,
    headers: [String: String]? = nil,
    providerOptions: ProviderOptions? = nil,
    telemetry: TelemetryOptions? = nil,
    runtimeContext: Context = [:],
    onStart: EmbedCallback<EmbedStartEvent<[String]>>? = nil,
    onEnd: EmbedCallback<EmbedEndEvent<[String], [Embedding]>>? = nil
) async throws -> DefaultEmbedManyResult<String> {
    try validateEmbeddingDimensions(dimensions)
    let model = try resolveEmbeddingModelV4(modelArg)

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
        runtimeContext: runtimeContext, callId: callId, operationId: "ai.embedMany",
        provider: model.provider, modelId: model.modelId, value: values,
        dimensions: dimensions, maxRetries: preparedRetries.maxRetries,
        headers: headersWithUserAgent, providerOptions: providerOptions
    )
    await notify(
        invoke(onStart, with: startEvent),
        { await dispatcher.onStart(.embedMany(startEvent)) }
    )

    @Sendable func embedChunk(_ chunk: [String], providerOptions: ProviderOptions?) async throws -> SingleCallResult {
        try await preparedRetries.retry.call {
            let embedCallId = generateCallId()
            await dispatcher.onEmbedStart(EmbeddingModelCallStartEvent(
                callId: callId, embedCallId: embedCallId, operationId: "ai.embedMany.doEmbed",
                provider: model.provider, modelId: model.modelId, values: chunk, dimensions: dimensions
            ))

            let modelResponse = try await model.doEmbed(
                options: EmbeddingModelV4CallOptions(
                    values: chunk,
                    dimensions: dimensions,
                    abortSignal: abortSignal,
                    providerOptions: providerOptions,
                    headers: headersWithUserAgent
                )
            )
            let usage = makeEmbeddingUsage(from: modelResponse.usage)

            await dispatcher.onEmbedEnd(EmbeddingModelCallEndEvent(
                callId: callId, embedCallId: embedCallId, operationId: "ai.embedMany.doEmbed",
                provider: model.provider, modelId: model.modelId, values: chunk,
                embeddings: modelResponse.embeddings, usage: usage
            ))

            return SingleCallResult(
                embeddings: modelResponse.embeddings,
                usage: usage,
                warnings: modelResponse.warnings,
                providerMetadata: modelResponse.providerMetadata,
                response: modelResponse.response
            )
        }
    }

    func finish(
        embeddings: [Embedding],
        usage: EmbeddingModelUsage,
        warnings: [SharedV4Warning],
        providerMetadata: ProviderMetadata?,
        responses: [EmbeddingModelV4ResponseInfo?]
    ) async -> DefaultEmbedManyResult<String> {
        logWarnings(warnings.map { .embeddingModel($0) })

        let endEvent = EmbedEndEvent(
            runtimeContext: runtimeContext, callId: callId, operationId: "ai.embedMany",
            provider: model.provider, modelId: model.modelId, value: values,
            embedding: embeddings, usage: usage, warnings: warnings,
            providerMetadata: providerMetadata, response: .many(responses)
        )
        await notify(
            invoke(onEnd, with: endEvent),
            { await dispatcher.onEnd(.embedMany(endEvent)) }
        )

        return DefaultEmbedManyResult(
            values: values,
            embeddings: embeddings,
            usage: usage,
            warnings: warnings,
            providerMetadata: providerMetadata,
            responses: responses
        )
    }

    do {
        async let maxEmbeddingsPerCallPromise = model.maxEmbeddingsPerCall
        async let supportsParallelCallsPromise = model.supportsParallelCalls
        async let maxInputBytesPromise = (model as? any EmbeddingModelMaxInputBytesPerCall)?.maxInputBytesPerCall

        let (maxEmbeddingsPerCall, supportsParallelCalls, maxInputBytesPerCall) = try await (
            maxEmbeddingsPerCallPromise,
            supportsParallelCallsPromise,
            maxInputBytesPromise
        )

        if (maxEmbeddingsPerCall == nil || maxEmbeddingsPerCall == .max)
            && (maxInputBytesPerCall == nil || maxInputBytesPerCall == .max) {
            let result = try await embedChunk(values, providerOptions: providerOptions)
            try validateEmbeddingCount(result.embeddings, values: values)

            return await finish(
                embeddings: result.embeddings,
                usage: result.usage,
                warnings: result.warnings,
                providerMetadata: result.providerMetadata,
                responses: [result.response]
            )
        }

        let valueChunks = try splitEmbeddingValues(
            values,
            maxEmbeddingsPerCall: maxEmbeddingsPerCall ?? .max,
            maxInputBytesPerCall: maxInputBytesPerCall ?? .max
        )

        let effectiveParallelLimit = supportsParallelCalls ? (maxParallelCalls ?? .max) : 1
        let parallelChunkSize = min(effectiveParallelLimit, max(valueChunks.count, 1))

        let parallelChunks = try splitArray(valueChunks, chunkSize: parallelChunkSize)

        var collectedEmbeddings: [Embedding] = []
        collectedEmbeddings.reserveCapacity(values.count)
        var collectedWarnings: [SharedV4Warning] = []
        var collectedResponses: [EmbeddingModelV4ResponseInfo?] = []
        collectedResponses.reserveCapacity(valueChunks.count)
        var totalTokens: Double = 0
        var aggregatedMetadata: ProviderMetadata?

        var nextChunkStartIndex = 0
        for parallelChunk in parallelChunks {
            var results = [SingleCallResult?](repeating: nil, count: parallelChunk.count)

            try await withThrowingTaskGroup(of: (Int, SingleCallResult).self) { group in
                for (index, chunk) in parallelChunk.enumerated() {
                    let startIndex = nextChunkStartIndex
                    nextChunkStartIndex += chunk.count
                    group.addTask {
                        let chunkProviderOptions: ProviderOptions?
                        if let transformer = model as? any EmbeddingModelProviderOptionsTransformer {
                            chunkProviderOptions = try await transformer.transformProviderOptions(.init(
                                providerOptions: providerOptions,
                                values: values,
                                startIndex: startIndex,
                                endIndex: startIndex + chunk.count
                            ))
                        } else {
                            chunkProviderOptions = providerOptions
                        }
                        let result = try await embedChunk(chunk, providerOptions: chunkProviderOptions)
                        try validateEmbeddingCount(result.embeddings, values: chunk)
                        return (index, result)
                    }
                }

                for try await (index, result) in group {
                    results[index] = result
                }
            }

            for case let result? in results {
                collectedEmbeddings.append(contentsOf: result.embeddings)
                collectedWarnings.append(contentsOf: result.warnings)
                collectedResponses.append(result.response)
                totalTokens += result.usage.tokens
                mergeProviderMetadata(target: &aggregatedMetadata, source: result.providerMetadata)
            }
        }

        return await finish(
            embeddings: collectedEmbeddings,
            usage: EmbeddingModelUsage(tokens: totalTokens),
            warnings: collectedWarnings,
            providerMetadata: aggregatedMetadata,
            responses: collectedResponses
        )
    } catch {
        await dispatcher.onError(callId: callId, error: error)
        throw error
    }
}

// MARK: - Convenience overloads (DX parity with TS)

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func embedMany(
    model: any EmbeddingModelV4,
    values: [String],
    dimensions: Int? = nil,
    maxParallelCalls: Int? = nil,
    maxRetries: Int? = nil,
    abortSignal: (@Sendable () -> Bool)? = nil,
    headers: [String: String]? = nil,
    providerOptions: ProviderOptions? = nil,
    telemetry: TelemetryOptions? = nil,
    runtimeContext: Context = [:],
    onStart: EmbedCallback<EmbedStartEvent<[String]>>? = nil,
    onEnd: EmbedCallback<EmbedEndEvent<[String], [Embedding]>>? = nil
) async throws -> DefaultEmbedManyResult<String> {
    try await embedMany(
        model: .v4(model),
        values: values,
        dimensions: dimensions,
        maxParallelCalls: maxParallelCalls,
        maxRetries: maxRetries,
        abortSignal: abortSignal,
        headers: headers,
        providerOptions: providerOptions,
        telemetry: telemetry,
        runtimeContext: runtimeContext,
        onStart: onStart,
        onEnd: onEnd
    )
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func embedMany(
    model: any EmbeddingModelV3<String>,
    values: [String],
    dimensions: Int? = nil,
    maxParallelCalls: Int? = nil,
    maxRetries: Int? = nil,
    abortSignal: (@Sendable () -> Bool)? = nil,
    headers: [String: String]? = nil,
    providerOptions: ProviderOptions? = nil,
    telemetry: TelemetryOptions? = nil,
    runtimeContext: Context = [:],
    onStart: EmbedCallback<EmbedStartEvent<[String]>>? = nil,
    onEnd: EmbedCallback<EmbedEndEvent<[String], [Embedding]>>? = nil
) async throws -> DefaultEmbedManyResult<String> {
    try await embedMany(
        model: .v3(model),
        values: values,
        dimensions: dimensions,
        maxParallelCalls: maxParallelCalls,
        maxRetries: maxRetries,
        abortSignal: abortSignal,
        headers: headers,
        providerOptions: providerOptions,
        telemetry: telemetry,
        runtimeContext: runtimeContext,
        onStart: onStart,
        onEnd: onEnd
    )
}

// MARK: - Internal Types

private struct SingleCallResult: Sendable {
    let embeddings: [Embedding]
    let usage: EmbeddingModelUsage
    let warnings: [SharedV4Warning]
    let providerMetadata: ProviderMetadata?
    let response: EmbeddingModelV4ResponseInfo?
}
