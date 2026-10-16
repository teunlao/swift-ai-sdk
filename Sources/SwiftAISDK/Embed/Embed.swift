import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Embed a single value using an embedding model.

 Port of `@ai-sdk/ai/src/embed/embed.ts`.
 */
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func embed(
    model modelArg: EmbeddingModel,
    value: String,
    dimensions: Int? = nil,
    providerOptions: ProviderOptions? = nil,
    maxRetries: Int? = nil,
    abortSignal: (@Sendable () -> Bool)? = nil,
    headers: [String: String]? = nil,
    experimentalTelemetry telemetry: TelemetrySettings? = nil,
    runtimeContext: [String: any Sendable] = [:],
    onStart: (@Sendable (EmbedStartEvent<String>) async throws -> Void)? = nil,
    experimentalOnStart: (@Sendable (EmbedStartEvent<String>) async throws -> Void)? = nil,
    onEnd: (@Sendable (EmbedEndEvent<String, Embedding>) async throws -> Void)? = nil,
    experimentalOnEnd: (@Sendable (EmbedEndEvent<String, Embedding>) async throws -> Void)? = nil
) async throws -> DefaultEmbedResult<String> {
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
        operationId: "ai.embed",
        telemetry: telemetry,
        baseAttributes: baseTelemetryAttributes,
        additional: [
            "ai.value": .input {
                .string(embedTelemetryJSONString(from: value))
            }
        ]
    )

    let outerAttributes = try await selectTelemetryAttributes(
        telemetry: telemetry,
        attributes: outerAttributeDescriptors
    )

    let callId = try createIDGenerator(prefix: "call", size: 24)()
    return try await recordSpan(
        name: "ai.embed",
        tracer: tracer,
        attributes: outerAttributes
    ) { span in
        try? await (onStart ?? experimentalOnStart)?(EmbedStartEvent(
            runtimeContext: runtimeContext, callId: callId, operationId: "ai.embed",
            provider: model.provider, modelId: model.modelId, value: value,
            dimensions: dimensions, maxRetries: preparedRetries.maxRetries,
            headers: headersWithUserAgent, providerOptions: providerOptions
        ))
        let (embedding, usage, warnings, providerMetadata, providerResponse) = try await preparedRetries.retry.call {
            try await recordSpan(
                name: "ai.embed.doEmbed",
                tracer: tracer,
                attributes: try await selectTelemetryAttributes(
                    telemetry: telemetry,
                    attributes: makeEmbedTelemetryAttributes(
                        operationId: "ai.embed.doEmbed",
                        telemetry: telemetry,
                        baseAttributes: baseTelemetryAttributes,
                        additional: [
                            "ai.values": .input {
                                .stringArray(embedTelemetryJSONStringArray(from: [value as Any]))
                            }
                        ]
                    )
                )
            ) { doEmbedSpan in
                let modelResponse = try await model.doEmbed(
                    options: EmbeddingModelV4CallOptions(
                        values: [value],
                        dimensions: dimensions,
                        abortSignal: abortSignal,
                        providerOptions: providerOptions,
                        headers: headersWithUserAgent
                    )
                )

                guard let embedding = modelResponse.embeddings.first else {
                    throw InvalidResponseDataError(
                        data: modelResponse.embeddings,
                        message: "No embedding generated."
                    )
                }
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

                return (
                    embedding,
                    usage,
                    modelResponse.warnings,
                    modelResponse.providerMetadata,
                    modelResponse.response
                )
            }
        }

        logWarnings(warnings.map { .embeddingModel($0) })

        let outerResultAttributes = try await selectTelemetryAttributes(
            telemetry: telemetry,
            attributes: [
                "ai.embedding": .output {
                    .string(embedTelemetryJSONString(from: embedding))
                },
                "ai.usage.tokens": .value(embeddingTokenAttribute(usage.tokens))
            ]
        )

        span.setAttributes(outerResultAttributes)

        try? await (onEnd ?? experimentalOnEnd)?(EmbedEndEvent(
            runtimeContext: runtimeContext, callId: callId, operationId: "ai.embed",
            provider: model.provider, modelId: model.modelId, value: value,
            embedding: embedding, usage: usage, warnings: warnings,
            providerMetadata: providerMetadata, response: .single(providerResponse)
        ))
        return DefaultEmbedResult(
            value: value,
            embedding: embedding,
            usage: usage,
            warnings: warnings,
            providerMetadata: providerMetadata,
            response: providerResponse
        )
    }
}

// MARK: - Convenience overloads (DX parity with TS)

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func embed(
    model: any EmbeddingModelV4,
    value: String,
    dimensions: Int? = nil,
    providerOptions: ProviderOptions? = nil,
    maxRetries: Int? = nil,
    abortSignal: (@Sendable () -> Bool)? = nil,
    headers: [String: String]? = nil,
    experimentalTelemetry telemetry: TelemetrySettings? = nil,
    runtimeContext: [String: any Sendable] = [:],
    onStart: (@Sendable (EmbedStartEvent<String>) async throws -> Void)? = nil,
    experimentalOnStart: (@Sendable (EmbedStartEvent<String>) async throws -> Void)? = nil,
    onEnd: (@Sendable (EmbedEndEvent<String, Embedding>) async throws -> Void)? = nil,
    experimentalOnEnd: (@Sendable (EmbedEndEvent<String, Embedding>) async throws -> Void)? = nil
) async throws -> DefaultEmbedResult<String> {
    try await embed(
        model: .v4(model),
        value: value,
        dimensions: dimensions,
        providerOptions: providerOptions,
        maxRetries: maxRetries,
        abortSignal: abortSignal,
        headers: headers,
        experimentalTelemetry: telemetry,
        runtimeContext: runtimeContext,
        onStart: onStart,
        experimentalOnStart: experimentalOnStart,
        onEnd: onEnd,
        experimentalOnEnd: experimentalOnEnd
    )
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func embed(
    model: any EmbeddingModelV3<String>,
    value: String,
    dimensions: Int? = nil,
    providerOptions: ProviderOptions? = nil,
    maxRetries: Int? = nil,
    abortSignal: (@Sendable () -> Bool)? = nil,
    headers: [String: String]? = nil,
    experimentalTelemetry telemetry: TelemetrySettings? = nil,
    runtimeContext: [String: any Sendable] = [:],
    onStart: (@Sendable (EmbedStartEvent<String>) async throws -> Void)? = nil,
    experimentalOnStart: (@Sendable (EmbedStartEvent<String>) async throws -> Void)? = nil,
    onEnd: (@Sendable (EmbedEndEvent<String, Embedding>) async throws -> Void)? = nil,
    experimentalOnEnd: (@Sendable (EmbedEndEvent<String, Embedding>) async throws -> Void)? = nil
) async throws -> DefaultEmbedResult<String> {
    try await embed(
        model: .v3(model),
        value: value,
        dimensions: dimensions,
        providerOptions: providerOptions,
        maxRetries: maxRetries,
        abortSignal: abortSignal,
        headers: headers,
        experimentalTelemetry: telemetry,
        runtimeContext: runtimeContext,
        onStart: onStart,
        experimentalOnStart: experimentalOnStart,
        onEnd: onEnd,
        experimentalOnEnd: experimentalOnEnd
    )
}
