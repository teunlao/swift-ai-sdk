import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Embed a single value using an embedding model.

 Port of `@ai-sdk/ai/src/embed/embed.ts`.
 */
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func embed<Value: Sendable>(
    model modelArg: EmbeddingModel<Value>,
    value: Value,
    providerOptions: ProviderOptions? = nil,
    maxRetries: Int? = nil,
    abortSignal: (@Sendable () -> Bool)? = nil,
    headers: [String: String]? = nil,
    experimentalTelemetry telemetry: TelemetrySettings? = nil
) async throws -> DefaultEmbedResult<Value> {
    let model = try resolveEmbeddingModel(modelArg)

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

    return try await recordSpan(
        name: "ai.embed",
        tracer: tracer,
        attributes: outerAttributes
    ) { span in
        let (embedding, usage, providerMetadata, providerResponse) = try await preparedRetries.retry.call {
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
                    options: EmbeddingModelV3DoEmbedOptions(
                        values: [value],
                        abortSignal: abortSignal,
                        providerOptions: providerOptions,
                        headers: headersWithUserAgent
                    )
                )

                let embedding = modelResponse.embeddings.first ?? []
                let usage = makeEmbeddingUsage(from: modelResponse.usage)

                let innerAttributes = try await selectTelemetryAttributes(
                    telemetry: telemetry,
                    attributes: [
                        "ai.embeddings": .output {
                            .stringArray(
                                embedTelemetryJSONStringArray(from: modelResponse.embeddings.map { $0 as Any })
                            )
                        },
                        "ai.usage.tokens": .value(.int(usage.tokens))
                    ]
                )

                doEmbedSpan.setAttributes(innerAttributes)

                return (
                    embedding,
                    usage,
                    modelResponse.providerMetadata,
                    modelResponse.response
                )
            }
        }

        let outerResultAttributes = try await selectTelemetryAttributes(
            telemetry: telemetry,
            attributes: [
                "ai.embedding": .output {
                    .string(embedTelemetryJSONString(from: embedding))
                },
                "ai.usage.tokens": .value(.int(usage.tokens))
            ]
        )

        span.setAttributes(outerResultAttributes)

        return DefaultEmbedResult(
            value: value,
            embedding: embedding,
            usage: usage,
            providerMetadata: providerMetadata,
            response: providerResponse
        )
    }
}

// MARK: - Convenience overloads (DX parity with TS)

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func embed<Value: Sendable>(
    model: any EmbeddingModelV3<Value>,
    value: Value,
    providerOptions: ProviderOptions? = nil,
    maxRetries: Int? = nil,
    abortSignal: (@Sendable () -> Bool)? = nil,
    headers: [String: String]? = nil,
    experimentalTelemetry telemetry: TelemetrySettings? = nil
) async throws -> DefaultEmbedResult<Value> {
    try await embed(
        model: .v3(model),
        value: value,
        providerOptions: providerOptions,
        maxRetries: maxRetries,
        abortSignal: abortSignal,
        headers: headers,
        experimentalTelemetry: telemetry
    )
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func embed<Value: Sendable>(
    model: any EmbeddingModelV2<Value>,
    value: Value,
    providerOptions: ProviderOptions? = nil,
    maxRetries: Int? = nil,
    abortSignal: (@Sendable () -> Bool)? = nil,
    headers: [String: String]? = nil,
    experimentalTelemetry telemetry: TelemetrySettings? = nil
) async throws -> DefaultEmbedResult<Value> {
    try await embed(
        model: .v2(model),
        value: value,
        providerOptions: providerOptions,
        maxRetries: maxRetries,
        abortSignal: abortSignal,
        headers: headers,
        experimentalTelemetry: telemetry
    )
}
