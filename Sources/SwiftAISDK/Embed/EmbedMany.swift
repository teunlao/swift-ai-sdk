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
    experimentalTelemetry telemetry: TelemetrySettings? = nil,
    runtimeContext: [String: any Sendable] = [:],
    onStart: (@Sendable (EmbedStartEvent<[String]>) async throws -> Void)? = nil,
    experimentalOnStart: (@Sendable (EmbedStartEvent<[String]>) async throws -> Void)? = nil,
    onEnd: (@Sendable (EmbedEndEvent<[String], [Embedding]>) async throws -> Void)? = nil,
    experimentalOnEnd: (@Sendable (EmbedEndEvent<[String], [Embedding]>) async throws -> Void)? = nil
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

    var telemetrySettings = CallSettings()
    telemetrySettings.maxRetries = preparedRetries.maxRetries

    let baseTelemetryAttributes = getBaseTelemetryAttributes(
        model: TelemetryModelInfo(modelId: model.modelId, provider: model.provider),
        settings: telemetrySettings,
        telemetry: telemetry,
        headers: headersWithUserAgent
    )

    let tracer = getTracer(
        isEnabled: telemetry?.isEnabled ?? false,
        tracer: telemetry?.tracer
    )

    let outerAttributeDescriptors = makeEmbedTelemetryAttributes(
        operationId: "ai.embedMany",
        telemetry: telemetry,
        baseAttributes: baseTelemetryAttributes,
        additional: [
            "ai.values": .input {
                .stringArray(embedTelemetryJSONStringArray(from: values.map { $0 as Any }))
            }
        ]
    )

    let outerAttributes = try await selectTelemetryAttributes(
        telemetry: telemetry,
        attributes: outerAttributeDescriptors
    )

    let callId = try createIDGenerator(prefix: "call", size: 24)()
    return try await recordSpan(
        name: "ai.embedMany",
        tracer: tracer,
        attributes: outerAttributes
    ) { span in
        try? await (onStart ?? experimentalOnStart)?(EmbedStartEvent(
            runtimeContext: runtimeContext, callId: callId, operationId: "ai.embedMany",
            provider: model.provider, modelId: model.modelId, value: values,
            dimensions: dimensions, maxRetries: preparedRetries.maxRetries,
            headers: headersWithUserAgent, providerOptions: providerOptions
        ))
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
            let result = try await preparedRetries.retry.call {
                try await recordSpan(
                    name: "ai.embedMany.doEmbed",
                    tracer: tracer,
                    attributes: try await selectTelemetryAttributes(
                        telemetry: telemetry,
                        attributes: makeEmbedTelemetryAttributes(
                            operationId: "ai.embedMany.doEmbed",
                            telemetry: telemetry,
                            baseAttributes: baseTelemetryAttributes,
                            additional: [
                                "ai.values": .input {
                                    .stringArray(embedTelemetryJSONStringArray(from: values.map { $0 as Any }))
                                }
                            ]
                        )
                    )
                ) { doEmbedSpan in
                    let modelResponse = try await model.doEmbed(
                        options: EmbeddingModelV4CallOptions(
                            values: values,
                            dimensions: dimensions,
                            abortSignal: abortSignal,
                            providerOptions: providerOptions,
                            headers: headersWithUserAgent
                        )
                    )

                    let usage = makeEmbeddingUsage(from: modelResponse.usage)

                    let innerAttributes = try await selectTelemetryAttributes(
                        telemetry: telemetry,
                        attributes: [
                            "ai.embeddings": .output {
                                .stringArray(
                                    embedTelemetryJSONStringArray(from: modelResponse.embeddings.map { $0 as Any })
                                )
                            },
                            "ai.usage.tokens": .value(embeddingTokenAttribute(usage.tokens))
                        ]
                    )

                    doEmbedSpan.setAttributes(innerAttributes)

                    return SingleCallResult(
                        embeddings: modelResponse.embeddings,
                        usage: usage,
                        warnings: modelResponse.warnings,
                        providerMetadata: modelResponse.providerMetadata,
                        response: modelResponse.response
                    )
                }
            }

            try validateEmbeddingCount(result.embeddings, values: values)

            let outerAttributesSingleCall = try await selectTelemetryAttributes(
                telemetry: telemetry,
                attributes: [
                    "ai.embeddings": .output {
                        .stringArray(
                            embedTelemetryJSONStringArray(from: result.embeddings.map { $0 as Any })
                        )
                    },
                    "ai.usage.tokens": .value(embeddingTokenAttribute(result.usage.tokens))
                ]
            )

            span.setAttributes(outerAttributesSingleCall)
            logWarnings(result.warnings.map { .embeddingModel($0) })

            try? await (onEnd ?? experimentalOnEnd)?(EmbedEndEvent(
                runtimeContext: runtimeContext, callId: callId, operationId: "ai.embedMany",
                provider: model.provider, modelId: model.modelId, value: values,
                embedding: result.embeddings, usage: result.usage, warnings: result.warnings,
                providerMetadata: result.providerMetadata, response: .many([result.response])
            ))
            return DefaultEmbedManyResult(
                values: values,
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
            var results = Array<SingleCallResult?>(repeating: nil, count: parallelChunk.count)

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
                        let result = try await preparedRetries.retry.call {
                            try await recordSpan(
                                name: "ai.embedMany.doEmbed",
                                tracer: tracer,
                                attributes: try await selectTelemetryAttributes(
                                    telemetry: telemetry,
                                    attributes: makeEmbedTelemetryAttributes(
                                        operationId: "ai.embedMany.doEmbed",
                                        telemetry: telemetry,
                                        baseAttributes: baseTelemetryAttributes,
                                        additional: [
                                            "ai.values": .input {
                                                .stringArray(embedTelemetryJSONStringArray(from: chunk.map { $0 as Any }))
                                            }
                                        ]
                                    )
                                )
                            ) { doEmbedSpan in
                                let modelResponse = try await model.doEmbed(
                                    options: EmbeddingModelV4CallOptions(
                                        values: chunk,
                                        dimensions: dimensions,
                                        abortSignal: abortSignal,
                                        providerOptions: chunkProviderOptions,
                                        headers: headersWithUserAgent
                                    )
                                )

                                let usage = makeEmbeddingUsage(from: modelResponse.usage)

                                let innerAttributes = try await selectTelemetryAttributes(
                                    telemetry: telemetry,
                                    attributes: [
                                        "ai.embeddings": .output {
                                            .stringArray(
                                                embedTelemetryJSONStringArray(from: modelResponse.embeddings.map { $0 as Any })
                                            )
                                        },
                                        "ai.usage.tokens": .value(embeddingTokenAttribute(usage.tokens))
                                    ]
                                )

                                doEmbedSpan.setAttributes(innerAttributes)

                                return SingleCallResult(
                                    embeddings: modelResponse.embeddings,
                                    usage: usage,
                                    warnings: modelResponse.warnings,
                                    providerMetadata: modelResponse.providerMetadata,
                                    response: modelResponse.response
                                )
                            }
                        }

                        try validateEmbeddingCount(result.embeddings, values: chunk)
                        return (index, result)
                    }
                }

                for try await (index, result) in group {
                    results[index] = result
                }
            }

            for maybeResult in results {
                guard let result = maybeResult else {
                    continue
                }

                collectedEmbeddings.append(contentsOf: result.embeddings)
                collectedWarnings.append(contentsOf: result.warnings)
                collectedResponses.append(result.response)
                totalTokens += result.usage.tokens
                mergeProviderMetadata(target: &aggregatedMetadata, source: result.providerMetadata)
            }
        }

        let telemetryEmbeddings = collectedEmbeddings
        let totalUsageTokens = totalTokens

        let outerAttributesMultiCall = try await selectTelemetryAttributes(
            telemetry: telemetry,
            attributes: [
                "ai.embeddings": .output {
                    .stringArray(
                        embedTelemetryJSONStringArray(from: telemetryEmbeddings.map { $0 as Any })
                    )
                },
                "ai.usage.tokens": .value(embeddingTokenAttribute(totalUsageTokens))
            ]
        )

        span.setAttributes(outerAttributesMultiCall)
        logWarnings(collectedWarnings.map { .embeddingModel($0) })

        try? await (onEnd ?? experimentalOnEnd)?(EmbedEndEvent(
            runtimeContext: runtimeContext, callId: callId, operationId: "ai.embedMany",
            provider: model.provider, modelId: model.modelId, value: values,
            embedding: collectedEmbeddings, usage: EmbeddingModelUsage(tokens: totalTokens),
            warnings: collectedWarnings, providerMetadata: aggregatedMetadata,
            response: .many(collectedResponses)
        ))
        return DefaultEmbedManyResult(
            values: values,
            embeddings: telemetryEmbeddings,
            usage: EmbeddingModelUsage(tokens: totalUsageTokens),
            warnings: collectedWarnings,
            providerMetadata: aggregatedMetadata,
            responses: collectedResponses
        )
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
    experimentalTelemetry telemetry: TelemetrySettings? = nil,
    runtimeContext: [String: any Sendable] = [:],
    onStart: (@Sendable (EmbedStartEvent<[String]>) async throws -> Void)? = nil,
    experimentalOnStart: (@Sendable (EmbedStartEvent<[String]>) async throws -> Void)? = nil,
    onEnd: (@Sendable (EmbedEndEvent<[String], [Embedding]>) async throws -> Void)? = nil,
    experimentalOnEnd: (@Sendable (EmbedEndEvent<[String], [Embedding]>) async throws -> Void)? = nil
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
        experimentalTelemetry: telemetry,
        runtimeContext: runtimeContext,
        onStart: onStart,
        experimentalOnStart: experimentalOnStart,
        onEnd: onEnd,
        experimentalOnEnd: experimentalOnEnd
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
    experimentalTelemetry telemetry: TelemetrySettings? = nil,
    runtimeContext: [String: any Sendable] = [:],
    onStart: (@Sendable (EmbedStartEvent<[String]>) async throws -> Void)? = nil,
    experimentalOnStart: (@Sendable (EmbedStartEvent<[String]>) async throws -> Void)? = nil,
    onEnd: (@Sendable (EmbedEndEvent<[String], [Embedding]>) async throws -> Void)? = nil,
    experimentalOnEnd: (@Sendable (EmbedEndEvent<[String], [Embedding]>) async throws -> Void)? = nil
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
        experimentalTelemetry: telemetry,
        runtimeContext: runtimeContext,
        onStart: onStart,
        experimentalOnStart: experimentalOnStart,
        onEnd: onEnd,
        experimentalOnEnd: experimentalOnEnd
    )
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func embedMany(
    model: any EmbeddingModelV2<String>,
    values: [String],
    dimensions: Int? = nil,
    maxParallelCalls: Int? = nil,
    maxRetries: Int? = nil,
    abortSignal: (@Sendable () -> Bool)? = nil,
    headers: [String: String]? = nil,
    providerOptions: ProviderOptions? = nil,
    experimentalTelemetry telemetry: TelemetrySettings? = nil,
    runtimeContext: [String: any Sendable] = [:],
    onStart: (@Sendable (EmbedStartEvent<[String]>) async throws -> Void)? = nil,
    experimentalOnStart: (@Sendable (EmbedStartEvent<[String]>) async throws -> Void)? = nil,
    onEnd: (@Sendable (EmbedEndEvent<[String], [Embedding]>) async throws -> Void)? = nil,
    experimentalOnEnd: (@Sendable (EmbedEndEvent<[String], [Embedding]>) async throws -> Void)? = nil
) async throws -> DefaultEmbedManyResult<String> {
    try await embedMany(
        model: .v2(model),
        values: values,
        dimensions: dimensions,
        maxParallelCalls: maxParallelCalls,
        maxRetries: maxRetries,
        abortSignal: abortSignal,
        headers: headers,
        providerOptions: providerOptions,
        experimentalTelemetry: telemetry,
        runtimeContext: runtimeContext,
        onStart: onStart,
        experimentalOnStart: experimentalOnStart,
        onEnd: onEnd,
        experimentalOnEnd: experimentalOnEnd
    )
}

// MARK: - Internal Types

private struct SingleCallResult {
    let embeddings: [Embedding]
    let usage: EmbeddingModelUsage
    let warnings: [SharedV4Warning]
    let providerMetadata: ProviderMetadata?
    let response: EmbeddingModelV4ResponseInfo?
}
