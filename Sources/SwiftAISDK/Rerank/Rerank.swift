import Foundation
import AISDKProvider
import AISDKProviderUtils

/// Callback for rerank operation lifecycle events.
public typealias RerankCallback<Event: Sendable> = @Sendable (Event) async throws -> Void

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func rerank(
    model: any RerankingModelConvertible,
    documents: [String],
    query: String,
    topN: Int? = nil,
    maxRetries: Int? = nil,
    abortSignal: (@Sendable () -> Bool)? = nil,
    headers: [String: String]? = nil,
    providerOptions: ProviderOptions? = nil,
    telemetry: TelemetryOptions? = nil,
    runtimeContext: Context = [:],
    onStart: RerankCallback<RerankStartEvent<String>>? = nil,
    onEnd: RerankCallback<RerankEndEvent<String>>? = nil
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
        onStart: onStart,
        onEnd: onEnd,
        telemetryDocument: { .string($0) }
    )
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func rerank(
    model: any RerankingModelConvertible,
    documents: [JSONObject],
    query: String,
    topN: Int? = nil,
    maxRetries: Int? = nil,
    abortSignal: (@Sendable () -> Bool)? = nil,
    headers: [String: String]? = nil,
    providerOptions: ProviderOptions? = nil,
    telemetry: TelemetryOptions? = nil,
    runtimeContext: Context = [:],
    onStart: RerankCallback<RerankStartEvent<JSONObject>>? = nil,
    onEnd: RerankCallback<RerankEndEvent<JSONObject>>? = nil
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
        onStart: onStart,
        onEnd: onEnd,
        telemetryDocument: { .object($0) }
    )
}

// MARK: - Implementation

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
private func _rerank<Value: Sendable>(
    model: any RerankingModelConvertible,
    documents: [Value],
    documentsToSend: RerankingModelV4CallOptions.Documents,
    query: String,
    topN: Int?,
    maxRetries: Int?,
    abortSignal: (@Sendable () -> Bool)?,
    headers: [String: String]?,
    providerOptions: ProviderOptions?,
    telemetry: TelemetryOptions?,
    runtimeContext: Context,
    onStart: RerankCallback<RerankStartEvent<Value>>?,
    onEnd: RerankCallback<RerankEndEvent<Value>>?,
    telemetryDocument: @escaping @Sendable (Value) -> JSONValue
) async throws -> DefaultRerankResult<Value> {
    let resolvedModel = try resolveRerankingModel(model)
    let callId = try createIDGenerator(prefix: "call", size: 24)()
    let dispatcher = TelemetryDispatcher(telemetry: telemetry)

    func notifyStart(_ event: RerankStartEvent<Value>) async {
        await notify(
            invoke(onStart, with: event),
            { await dispatcher.onStart(.rerank(event.mapDocuments(telemetryDocument))) }
        )
    }

    func notifyEnd(_ event: RerankEndEvent<Value>) async {
        await notify(
            invoke(onEnd, with: event),
            { await dispatcher.onEnd(.rerank(event.mapDocuments(telemetryDocument))) }
        )
    }

    if documents.isEmpty {
        await notifyStart(RerankStartEvent(
            runtimeContext: runtimeContext, callId: callId, operationId: "ai.rerank",
            provider: resolvedModel.provider, modelId: resolvedModel.modelId,
            documents: documents, query: query, topN: topN,
            maxRetries: maxRetries ?? 2, headers: headers, providerOptions: providerOptions
        ))
        let response = RerankResponse(timestamp: Date(), modelId: resolvedModel.modelId)
        await notifyEnd(RerankEndEvent(
            runtimeContext: runtimeContext, callId: callId, operationId: "ai.rerank",
            provider: resolvedModel.provider, modelId: resolvedModel.modelId,
            documents: documents, query: query, ranking: [], warnings: [],
            providerMetadata: nil, response: response
        ))
        return DefaultRerankResult(
            originalDocuments: [],
            ranking: [],
            providerMetadata: nil,
            response: response
        )
    }

    let preparedRetries = try prepareRetries(
        maxRetries: maxRetries,
        abortSignal: abortSignal
    )

    await notifyStart(RerankStartEvent(
        runtimeContext: runtimeContext, callId: callId, operationId: "ai.rerank",
        provider: resolvedModel.provider, modelId: resolvedModel.modelId,
        documents: documents, query: query, topN: topN,
        maxRetries: preparedRetries.maxRetries, headers: headers, providerOptions: providerOptions
    ))

    let documentsType = rerankDocumentsTypeString(documentsToSend)

    do {
        let (ranking, providerMetadata, responseInfo, warnings) = try await preparedRetries.retry.call {
            await dispatcher.onRerankStart(RerankingModelCallStartEvent(
                callId: callId, operationId: "ai.rerank.doRerank",
                provider: resolvedModel.provider, modelId: resolvedModel.modelId,
                documents: documents.map(telemetryDocument), documentsType: documentsType,
                query: query, topN: topN
            ))

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

            await dispatcher.onRerankEnd(RerankingModelCallEndEvent(
                callId: callId, operationId: "ai.rerank.doRerank",
                provider: resolvedModel.provider, modelId: resolvedModel.modelId,
                documentsType: documentsType, ranking: modelResponse.ranking
            ))

            return (
                modelResponse.ranking,
                modelResponse.providerMetadata,
                modelResponse.response,
                modelResponse.warnings
            )
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

        await notifyEnd(RerankEndEvent(
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
    } catch {
        await dispatcher.onError(callId: callId, error: error)
        throw error
    }
}

private func rerankDocumentsTypeString(_ documents: RerankingModelV4CallOptions.Documents) -> String {
    switch documents {
    case .text:
        return "text"
    case .object:
        return "object"
    }
}
