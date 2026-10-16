import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Rerank documents using a reranking model.

 Port of `@ai-sdk/ai/src/rerank/rerank.ts`.
 */
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func rerank(
    model: any RerankingModelV3,
    documents: [String],
    query: String,
    topN: Int? = nil,
    maxRetries: Int? = nil,
    abortSignal: (@Sendable () -> Bool)? = nil,
    headers: [String: String]? = nil,
    providerOptions: ProviderOptions? = nil,
    experimentalTelemetry telemetry: TelemetrySettings? = nil,
    runtimeContext: [String: any Sendable] = [:],
    onStart: (@Sendable (RerankStartEvent<String>) async throws -> Void)? = nil,
    experimentalOnStart: (@Sendable (RerankStartEvent<String>) async throws -> Void)? = nil,
    onEnd: (@Sendable (RerankEndEvent<String>) async throws -> Void)? = nil,
    experimentalOnEnd: (@Sendable (RerankEndEvent<String>) async throws -> Void)? = nil
) async throws -> DefaultRerankResult<String> {
    try await rerank(
        model: .v3(model),
        documents: documents,
        query: query,
        topN: topN,
        maxRetries: maxRetries,
        abortSignal: abortSignal,
        headers: headers,
        providerOptions: providerOptions,
        experimentalTelemetry: telemetry,
        runtimeContext: runtimeContext,
        onStart: onStart, experimentalOnStart: experimentalOnStart,
        onEnd: onEnd, experimentalOnEnd: experimentalOnEnd
    )
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func rerank(
    model: any RerankingModelV4,
    documents: [String],
    query: String,
    topN: Int? = nil,
    maxRetries: Int? = nil,
    abortSignal: (@Sendable () -> Bool)? = nil,
    headers: [String: String]? = nil,
    providerOptions: ProviderOptions? = nil,
    experimentalTelemetry telemetry: TelemetrySettings? = nil,
    runtimeContext: [String: any Sendable] = [:],
    onStart: (@Sendable (RerankStartEvent<String>) async throws -> Void)? = nil,
    experimentalOnStart: (@Sendable (RerankStartEvent<String>) async throws -> Void)? = nil,
    onEnd: (@Sendable (RerankEndEvent<String>) async throws -> Void)? = nil,
    experimentalOnEnd: (@Sendable (RerankEndEvent<String>) async throws -> Void)? = nil
) async throws -> DefaultRerankResult<String> {
    try await rerank(
        model: .v4(model),
        documents: documents,
        query: query,
        topN: topN,
        maxRetries: maxRetries,
        abortSignal: abortSignal,
        headers: headers,
        providerOptions: providerOptions,
        experimentalTelemetry: telemetry,
        runtimeContext: runtimeContext,
        onStart: onStart, experimentalOnStart: experimentalOnStart,
        onEnd: onEnd, experimentalOnEnd: experimentalOnEnd
    )
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func rerank(
    model: RerankingModel,
    documents: [String],
    query: String,
    topN: Int? = nil,
    maxRetries: Int? = nil,
    abortSignal: (@Sendable () -> Bool)? = nil,
    headers: [String: String]? = nil,
    providerOptions: ProviderOptions? = nil,
    experimentalTelemetry telemetry: TelemetrySettings? = nil,
    runtimeContext: [String: any Sendable] = [:],
    onStart: (@Sendable (RerankStartEvent<String>) async throws -> Void)? = nil,
    experimentalOnStart: (@Sendable (RerankStartEvent<String>) async throws -> Void)? = nil,
    onEnd: (@Sendable (RerankEndEvent<String>) async throws -> Void)? = nil,
    experimentalOnEnd: (@Sendable (RerankEndEvent<String>) async throws -> Void)? = nil
) async throws -> DefaultRerankResult<String> {
    try await _rerank(
        model: model,
        documents: documents,
        documentsToSend: .text(values: documents),
        query: query,
        topN: topN,
        maxRetries: maxRetries,
        abortSignal: abortSignal,
        headers: headers,
        providerOptions: providerOptions,
        telemetry: telemetry,
        runtimeContext: runtimeContext,
        onStart: onStart ?? experimentalOnStart,
        onEnd: onEnd ?? experimentalOnEnd,
        stringifyDocumentForTelemetry: { doc in
            try jsonStringify(doc)
        }
    )
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func rerank(
    model: any RerankingModelV3,
    documents: [JSONObject],
    query: String,
    topN: Int? = nil,
    maxRetries: Int? = nil,
    abortSignal: (@Sendable () -> Bool)? = nil,
    headers: [String: String]? = nil,
    providerOptions: ProviderOptions? = nil,
    experimentalTelemetry telemetry: TelemetrySettings? = nil,
    runtimeContext: [String: any Sendable] = [:],
    onStart: (@Sendable (RerankStartEvent<JSONObject>) async throws -> Void)? = nil,
    experimentalOnStart: (@Sendable (RerankStartEvent<JSONObject>) async throws -> Void)? = nil,
    onEnd: (@Sendable (RerankEndEvent<JSONObject>) async throws -> Void)? = nil,
    experimentalOnEnd: (@Sendable (RerankEndEvent<JSONObject>) async throws -> Void)? = nil
) async throws -> DefaultRerankResult<JSONObject> {
    try await rerank(
        model: .v3(model),
        documents: documents,
        query: query,
        topN: topN,
        maxRetries: maxRetries,
        abortSignal: abortSignal,
        headers: headers,
        providerOptions: providerOptions,
        experimentalTelemetry: telemetry,
        runtimeContext: runtimeContext,
        onStart: onStart, experimentalOnStart: experimentalOnStart,
        onEnd: onEnd, experimentalOnEnd: experimentalOnEnd
    )
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func rerank(
    model: any RerankingModelV4,
    documents: [JSONObject],
    query: String,
    topN: Int? = nil,
    maxRetries: Int? = nil,
    abortSignal: (@Sendable () -> Bool)? = nil,
    headers: [String: String]? = nil,
    providerOptions: ProviderOptions? = nil,
    experimentalTelemetry telemetry: TelemetrySettings? = nil,
    runtimeContext: [String: any Sendable] = [:],
    onStart: (@Sendable (RerankStartEvent<JSONObject>) async throws -> Void)? = nil,
    experimentalOnStart: (@Sendable (RerankStartEvent<JSONObject>) async throws -> Void)? = nil,
    onEnd: (@Sendable (RerankEndEvent<JSONObject>) async throws -> Void)? = nil,
    experimentalOnEnd: (@Sendable (RerankEndEvent<JSONObject>) async throws -> Void)? = nil
) async throws -> DefaultRerankResult<JSONObject> {
    try await rerank(
        model: .v4(model),
        documents: documents,
        query: query,
        topN: topN,
        maxRetries: maxRetries,
        abortSignal: abortSignal,
        headers: headers,
        providerOptions: providerOptions,
        experimentalTelemetry: telemetry,
        runtimeContext: runtimeContext,
        onStart: onStart, experimentalOnStart: experimentalOnStart,
        onEnd: onEnd, experimentalOnEnd: experimentalOnEnd
    )
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func rerank(
    model: RerankingModel,
    documents: [JSONObject],
    query: String,
    topN: Int? = nil,
    maxRetries: Int? = nil,
    abortSignal: (@Sendable () -> Bool)? = nil,
    headers: [String: String]? = nil,
    providerOptions: ProviderOptions? = nil,
    experimentalTelemetry telemetry: TelemetrySettings? = nil,
    runtimeContext: [String: any Sendable] = [:],
    onStart: (@Sendable (RerankStartEvent<JSONObject>) async throws -> Void)? = nil,
    experimentalOnStart: (@Sendable (RerankStartEvent<JSONObject>) async throws -> Void)? = nil,
    onEnd: (@Sendable (RerankEndEvent<JSONObject>) async throws -> Void)? = nil,
    experimentalOnEnd: (@Sendable (RerankEndEvent<JSONObject>) async throws -> Void)? = nil
) async throws -> DefaultRerankResult<JSONObject> {
    try await _rerank(
        model: model,
        documents: documents,
        documentsToSend: .object(values: documents),
        query: query,
        topN: topN,
        maxRetries: maxRetries,
        abortSignal: abortSignal,
        headers: headers,
        providerOptions: providerOptions,
        telemetry: telemetry,
        runtimeContext: runtimeContext,
        onStart: onStart ?? experimentalOnStart,
        onEnd: onEnd ?? experimentalOnEnd,
        stringifyDocumentForTelemetry: { doc in
            try jsonStringify(doc)
        }
    )
}

// MARK: - Implementation

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
private func _rerank<Value: Sendable>(
    model: RerankingModel,
    documents: [Value],
    documentsToSend: RerankingModelV4CallOptions.Documents,
    query: String,
    topN: Int?,
    maxRetries: Int?,
    abortSignal: (@Sendable () -> Bool)?,
    headers: [String: String]?,
    providerOptions: ProviderOptions?,
    telemetry: TelemetrySettings?,
    runtimeContext: [String: any Sendable],
    onStart: (@Sendable (RerankStartEvent<Value>) async throws -> Void)?,
    onEnd: (@Sendable (RerankEndEvent<Value>) async throws -> Void)?,
    stringifyDocumentForTelemetry: @escaping @Sendable (Value) throws -> String
) async throws -> DefaultRerankResult<Value> {
    let resolvedModel = try resolveRerankingModelV4(model)

    let callId = try createIDGenerator(prefix: "call", size: 24)()
    let startEvent = RerankStartEvent(
        runtimeContext: runtimeContext, callId: callId, operationId: "ai.rerank",
        provider: resolvedModel.provider, modelId: resolvedModel.modelId,
        documents: documents, query: query, topN: topN,
        maxRetries: maxRetries ?? 2, headers: headers, providerOptions: providerOptions
    )
    if documents.isEmpty {
        try? await onStart?(startEvent)
        try? await onEnd?(RerankEndEvent(
            runtimeContext: runtimeContext, callId: callId, operationId: "ai.rerank",
            provider: resolvedModel.provider, modelId: resolvedModel.modelId,
            documents: documents, query: query, ranking: [], warnings: [],
            providerMetadata: nil, response: RerankResponse(timestamp: Date(), modelId: resolvedModel.modelId)
        ))
        return DefaultRerankResult(
            originalDocuments: [],
            ranking: [],
            providerMetadata: nil,
            response: RerankResponse(
                timestamp: Date(),
                modelId: resolvedModel.modelId
            )
        )
    }

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
        model: TelemetryModelInfo(modelId: resolvedModel.modelId, provider: resolvedModel.provider),
        settings: telemetrySettings,
        telemetry: telemetry,
        headers: headersWithUserAgent
    )

    let tracer = getTracer(
        isEnabled: telemetry?.isEnabled ?? false,
        tracer: telemetry?.tracer
    )

    let outerAttributes = try await selectTelemetryAttributes(
        telemetry: telemetry,
        attributes: makeRerankTelemetryAttributes(
            operationId: "ai.rerank",
            telemetry: telemetry,
            baseAttributes: baseTelemetryAttributes,
            additional: [
                "ai.documents": .input {
                    .stringArray(try documents.map(stringifyDocumentForTelemetry))
                }
            ]
        )
    )

    return try await recordSpan(
        name: "ai.rerank",
        tracer: tracer,
        attributes: outerAttributes
    ) { span in
        try? await onStart?(startEvent)
        let (ranking, providerMetadata, responseInfo, warnings) = try await preparedRetries.retry.call {
            try await recordSpan(
                name: "ai.rerank.doRerank",
                tracer: tracer,
                attributes: try await selectTelemetryAttributes(
                    telemetry: telemetry,
                    attributes: makeRerankTelemetryAttributes(
                        operationId: "ai.rerank.doRerank",
                        telemetry: telemetry,
                        baseAttributes: baseTelemetryAttributes,
                        additional: [
                            "ai.documents": .input {
                                .stringArray(try documents.map(stringifyDocumentForTelemetry))
                            }
                        ]
                    )
                )
            ) { doRerankSpan in
                let modelResponse = try await resolvedModel.doRerank(
                    options: RerankingModelV4CallOptions(
                        documents: documentsToSend,
                        query: query,
                        topN: topN,
                        abortSignal: abortSignal,
                        providerOptions: providerOptions,
                        headers: headers
                    )
                )

                let innerAttributes = try await selectTelemetryAttributes(
                    telemetry: telemetry,
                    attributes: [
                        "ai.ranking.type": .value(.string(rerankDocumentsTypeString(documentsToSend))),
                        "ai.ranking": .output {
                            .stringArray(try modelResponse.ranking.map { try jsonStringify($0) })
                        }
                    ]
                )

                doRerankSpan.setAttributes(innerAttributes)

                return (
                    modelResponse.ranking,
                    modelResponse.providerMetadata,
                    modelResponse.response,
                    modelResponse.warnings
                )
            }
        }

        for entry in ranking where !documents.indices.contains(entry.index) {
            throw InvalidResponseDataError(
                data: ranking,
                message: "Invalid ranking index \(entry.index). Expected an integer between 0 and \(documents.count - 1)."
            )
        }
        logWarnings(warnings.map { .rerankingModel($0) })

        let resolvedResponse = RerankResponse(
            id: responseInfo?.id,
            timestamp: responseInfo?.timestamp ?? Date(),
            modelId: responseInfo?.modelId ?? resolvedModel.modelId,
            headers: responseInfo?.headers,
            body: responseInfo?.body
        )

        let resolvedRanking = ranking.map { entry in
            RerankRanking(
                originalIndex: entry.index,
                score: entry.relevanceScore,
                document: documents[entry.index]
            )
        }

        let outerResultAttributes = try await selectTelemetryAttributes(
            telemetry: telemetry,
            attributes: [
                "ai.ranking": .output {
                    .stringArray(try ranking.map { try jsonStringify($0) })
                }
            ]
        )

        span.setAttributes(outerResultAttributes)

        try? await onEnd?(RerankEndEvent(
            runtimeContext: runtimeContext, callId: callId, operationId: "ai.rerank",
            provider: resolvedModel.provider, modelId: resolvedModel.modelId,
            documents: documents, query: query, ranking: resolvedRanking,
            warnings: warnings, providerMetadata: providerMetadata, response: resolvedResponse
        ))
        return DefaultRerankResult(
            originalDocuments: documents,
            ranking: resolvedRanking,
            providerMetadata: providerMetadata,
            response: resolvedResponse
        )
    }
}

private func makeRerankTelemetryAttributes(
    operationId: String,
    telemetry: TelemetrySettings?,
    baseAttributes: Attributes,
    additional: [String: ResolvableAttributeValue?] = [:]
) -> [String: ResolvableAttributeValue?] {
    var attributes: [String: ResolvableAttributeValue?] = [:]

    for (key, value) in assembleOperationName(operationId: operationId, telemetry: telemetry) {
        attributes[key] = .value(value)
    }

    for (key, value) in baseAttributes {
        attributes[key] = .value(value)
    }

    for (key, value) in additional {
        attributes[key] = value
    }

    return attributes
}

private func rerankDocumentsTypeString(_ documents: RerankingModelV4CallOptions.Documents) -> String {
    switch documents {
    case .text:
        return "text"
    case .object:
        return "object"
    }
}

private func jsonStringify<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(value)
    guard let string = String(data: data, encoding: .utf8) else {
        throw EncodingError.invalidValue(
            value,
            EncodingError.Context(codingPath: [], debugDescription: "Failed to encode JSON string")
        )
    }
    return string
}
