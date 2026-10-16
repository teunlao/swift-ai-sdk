import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Streams an object (JSON/array/enum/no-schema) from a language model with partial updates.

 Port of `@ai-sdk/ai/src/generate-object/stream-object.ts`. Callbacks run
 concurrently with the telemetry integrations; errors they throw are ignored.
 */
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func streamObject<ResultValue, PartialValue, ElementStream>(
    model modelArg: LanguageModel,
    output: GenerateObjectOutputSpec<ResultValue, PartialValue, ElementStream>,
    system: String? = nil,
    prompt: String? = nil,
    messages: [ModelMessage]? = nil,
    repairText: RepairTextFunction? = nil,
    telemetry: TelemetryOptions? = nil,
    experimentalDownload download: DownloadFunction? = nil,
    providerOptions: ProviderOptions? = nil,
    onStart: GenerateObjectCallback<GenerateObjectStartEvent>? = nil,
    onStepStart: GenerateObjectCallback<GenerateObjectStepStartEvent>? = nil,
    onStepEnd: GenerateObjectCallback<GenerateObjectStepEndEvent>? = nil,
    onError: StreamObjectOnErrorCallback? = nil,
    onFinish: GenerateObjectCallback<GenerateObjectEndEvent<ResultValue>>? = nil,
    internalOptions _internal: GenerateObjectInternalOptions = GenerateObjectInternalOptions(),
    settings: CallSettings = CallSettings()
) throws -> StreamObjectResult<PartialValue, ResultValue, ElementStream> {
    let model = try resolveLanguageModelV4(modelArg)

    try validateObjectGenerationInput(
        output: output.kind,
        hasSchema: output.kind == .object || output.kind == .array,
        schemaName: output.schemaName,
        schemaDescription: output.schemaDescription,
        enumValues: output.enumValues
    )

    let result = StreamObjectResult<PartialValue, ResultValue, ElementStream>(
        createElementStream: output.strategy.createElementStream
    )

    let errorHandler: StreamObjectOnErrorCallback = onError ?? { event in
        fputs("streamObject error: \(event.error)\n", stderr)
    }

    let run = StreamObjectRun(
        model: model,
        output: output,
        repairText: repairText,
        dispatcher: TelemetryDispatcher(telemetry: telemetry),
        download: download,
        providerOptions: providerOptions,
        onStart: onStart,
        onStepStart: onStepStart,
        onStepEnd: onStepEnd,
        errorHandler: errorHandler,
        onFinish: onFinish,
        internalOptions: _internal,
        settings: settings,
        system: system,
        prompt: prompt,
        messages: messages,
        result: result,
        callId: _internal.generateId()
    )

    Task {
        do {
            try await run.start()
        } catch {
            let normalized = (wrapGatewayError(error) as? Error) ?? error
            result.rejectPending(normalized)
            await run.dispatcher.onError(callId: run.callId, error: normalized)
            await errorHandler(StreamObjectErrorEvent(error: normalized))
            await result.publish(.error(AnySendableError(normalized)))
            await result.endStream(error: normalized)
        }
    }

    return result
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func streamObject<ObjectResult: Codable & Sendable>(
    model: LanguageModel,
    schema type: ObjectResult.Type,
    system: String? = nil,
    prompt: String? = nil,
    messages: [ModelMessage]? = nil,
    schemaName: String? = nil,
    schemaDescription: String? = nil,
    mode: GenerateObjectJSONMode = .auto,
    repairText: RepairTextFunction? = nil,
    telemetry: TelemetryOptions? = nil,
    experimentalDownload download: DownloadFunction? = nil,
    providerOptions: ProviderOptions? = nil,
    onStart: GenerateObjectCallback<GenerateObjectStartEvent>? = nil,
    onStepStart: GenerateObjectCallback<GenerateObjectStepStartEvent>? = nil,
    onStepEnd: GenerateObjectCallback<GenerateObjectStepEndEvent>? = nil,
    onError: StreamObjectOnErrorCallback? = nil,
    onFinish: GenerateObjectCallback<GenerateObjectEndEvent<ObjectResult>>? = nil,
    internalOptions: GenerateObjectInternalOptions = GenerateObjectInternalOptions(),
    settings: CallSettings = CallSettings()
) throws -> StreamObjectResult<[String: JSONValue], ObjectResult, Never> {
    try streamObject(
        model: model,
        schema: FlexibleSchema.auto(type),
        system: system,
        prompt: prompt,
        messages: messages,
        schemaName: schemaName,
        schemaDescription: schemaDescription,
        mode: mode,
        repairText: repairText,
        telemetry: telemetry,
        experimentalDownload: download,
        providerOptions: providerOptions,
        onStart: onStart,
        onStepStart: onStepStart,
        onStepEnd: onStepEnd,
        onError: onError,
        onFinish: onFinish,
        internalOptions: internalOptions,
        settings: settings
    )
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func streamObject<ObjectResult>(
    model: LanguageModel,
    schema: FlexibleSchema<ObjectResult>,
    system: String? = nil,
    prompt: String? = nil,
    messages: [ModelMessage]? = nil,
    schemaName: String? = nil,
    schemaDescription: String? = nil,
    mode: GenerateObjectJSONMode = .auto,
    repairText: RepairTextFunction? = nil,
    telemetry: TelemetryOptions? = nil,
    experimentalDownload download: DownloadFunction? = nil,
    providerOptions: ProviderOptions? = nil,
    onStart: GenerateObjectCallback<GenerateObjectStartEvent>? = nil,
    onStepStart: GenerateObjectCallback<GenerateObjectStepStartEvent>? = nil,
    onStepEnd: GenerateObjectCallback<GenerateObjectStepEndEvent>? = nil,
    onError: StreamObjectOnErrorCallback? = nil,
    onFinish: GenerateObjectCallback<GenerateObjectEndEvent<ObjectResult>>? = nil,
    internalOptions: GenerateObjectInternalOptions = GenerateObjectInternalOptions(),
    settings: CallSettings = CallSettings()
) throws -> StreamObjectResult<[String: JSONValue], ObjectResult, Never> {
    try streamObject(
        model: model,
        output: GenerateObjectOutput.object(
            schema: schema,
            schemaName: schemaName,
            schemaDescription: schemaDescription,
            mode: mode
        ),
        system: system,
        prompt: prompt,
        messages: messages,
        repairText: repairText,
        telemetry: telemetry,
        experimentalDownload: download,
        providerOptions: providerOptions,
        onStart: onStart,
        onStepStart: onStepStart,
        onStepEnd: onStepEnd,
        onError: onError,
        onFinish: onFinish,
        internalOptions: internalOptions,
        settings: settings
    )
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func streamObjectNoSchema(
    model: LanguageModel,
    system: String? = nil,
    prompt: String? = nil,
    messages: [ModelMessage]? = nil,
    repairText: RepairTextFunction? = nil,
    telemetry: TelemetryOptions? = nil,
    experimentalDownload download: DownloadFunction? = nil,
    providerOptions: ProviderOptions? = nil,
    onStart: GenerateObjectCallback<GenerateObjectStartEvent>? = nil,
    onStepStart: GenerateObjectCallback<GenerateObjectStepStartEvent>? = nil,
    onStepEnd: GenerateObjectCallback<GenerateObjectStepEndEvent>? = nil,
    onError: StreamObjectOnErrorCallback? = nil,
    onFinish: GenerateObjectCallback<GenerateObjectEndEvent<JSONValue>>? = nil,
    internalOptions: GenerateObjectInternalOptions = GenerateObjectInternalOptions(),
    settings: CallSettings = CallSettings()
) throws -> StreamObjectResult<JSONValue, JSONValue, Never> {
    try streamObject(
        model: model,
        output: GenerateObjectOutput.noSchema(),
        system: system,
        prompt: prompt,
        messages: messages,
        repairText: repairText,
        telemetry: telemetry,
        experimentalDownload: download,
        providerOptions: providerOptions,
        onStart: onStart,
        onStepStart: onStepStart,
        onStepEnd: onStepEnd,
        onError: onError,
        onFinish: onFinish,
        internalOptions: internalOptions,
        settings: settings
    )
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func streamObjectArray<ElementResult: Codable & Sendable>(
    model: LanguageModel,
    schema elementType: ElementResult.Type,
    system: String? = nil,
    prompt: String? = nil,
    messages: [ModelMessage]? = nil,
    schemaName: String? = nil,
    schemaDescription: String? = nil,
    mode: GenerateObjectJSONMode = .auto,
    repairText: RepairTextFunction? = nil,
    telemetry: TelemetryOptions? = nil,
    experimentalDownload download: DownloadFunction? = nil,
    providerOptions: ProviderOptions? = nil,
    onStart: GenerateObjectCallback<GenerateObjectStartEvent>? = nil,
    onStepStart: GenerateObjectCallback<GenerateObjectStepStartEvent>? = nil,
    onStepEnd: GenerateObjectCallback<GenerateObjectStepEndEvent>? = nil,
    onError: StreamObjectOnErrorCallback? = nil,
    onFinish: GenerateObjectCallback<GenerateObjectEndEvent<[ElementResult]>>? = nil,
    internalOptions: GenerateObjectInternalOptions = GenerateObjectInternalOptions(),
    settings: CallSettings = CallSettings()
) throws -> StreamObjectResult<[ElementResult], [ElementResult], AsyncIterableStream<ElementResult>> {
    try streamObjectArray(
        model: model,
        schema: FlexibleSchema.auto(elementType),
        system: system,
        prompt: prompt,
        messages: messages,
        schemaName: schemaName,
        schemaDescription: schemaDescription,
        mode: mode,
        repairText: repairText,
        telemetry: telemetry,
        experimentalDownload: download,
        providerOptions: providerOptions,
        onStart: onStart,
        onStepStart: onStepStart,
        onStepEnd: onStepEnd,
        onError: onError,
        onFinish: onFinish,
        internalOptions: internalOptions,
        settings: settings
    )
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func streamObjectArray<ElementResult>(
    model: LanguageModel,
    schema: FlexibleSchema<ElementResult>,
    system: String? = nil,
    prompt: String? = nil,
    messages: [ModelMessage]? = nil,
    schemaName: String? = nil,
    schemaDescription: String? = nil,
    mode: GenerateObjectJSONMode = .auto,
    repairText: RepairTextFunction? = nil,
    telemetry: TelemetryOptions? = nil,
    experimentalDownload download: DownloadFunction? = nil,
    providerOptions: ProviderOptions? = nil,
    onStart: GenerateObjectCallback<GenerateObjectStartEvent>? = nil,
    onStepStart: GenerateObjectCallback<GenerateObjectStepStartEvent>? = nil,
    onStepEnd: GenerateObjectCallback<GenerateObjectStepEndEvent>? = nil,
    onError: StreamObjectOnErrorCallback? = nil,
    onFinish: GenerateObjectCallback<GenerateObjectEndEvent<[ElementResult]>>? = nil,
    internalOptions: GenerateObjectInternalOptions = GenerateObjectInternalOptions(),
    settings: CallSettings = CallSettings()
) throws -> StreamObjectResult<[ElementResult], [ElementResult], AsyncIterableStream<ElementResult>> {
    try streamObject(
        model: model,
        output: GenerateObjectOutput.array(
            schema: schema,
            schemaName: schemaName,
            schemaDescription: schemaDescription,
            mode: mode
        ),
        system: system,
        prompt: prompt,
        messages: messages,
        repairText: repairText,
        telemetry: telemetry,
        experimentalDownload: download,
        providerOptions: providerOptions,
        onStart: onStart,
        onStepStart: onStepStart,
        onStepEnd: onStepEnd,
        onError: onError,
        onFinish: onFinish,
        internalOptions: internalOptions,
        settings: settings
    )
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func streamObjectEnum(
    model: LanguageModel,
    values: [String],
    system: String? = nil,
    prompt: String? = nil,
    messages: [ModelMessage]? = nil,
    repairText: RepairTextFunction? = nil,
    telemetry: TelemetryOptions? = nil,
    experimentalDownload download: DownloadFunction? = nil,
    providerOptions: ProviderOptions? = nil,
    onStart: GenerateObjectCallback<GenerateObjectStartEvent>? = nil,
    onStepStart: GenerateObjectCallback<GenerateObjectStepStartEvent>? = nil,
    onStepEnd: GenerateObjectCallback<GenerateObjectStepEndEvent>? = nil,
    onError: StreamObjectOnErrorCallback? = nil,
    onFinish: GenerateObjectCallback<GenerateObjectEndEvent<String>>? = nil,
    internalOptions: GenerateObjectInternalOptions = GenerateObjectInternalOptions(),
    settings: CallSettings = CallSettings()
) throws -> StreamObjectResult<String, String, Never> {
    try streamObject(
        model: model,
        output: GenerateObjectOutput.enumeration(values: values),
        system: system,
        prompt: prompt,
        messages: messages,
        repairText: repairText,
        telemetry: telemetry,
        experimentalDownload: download,
        providerOptions: providerOptions,
        onStart: onStart,
        onStepStart: onStepStart,
        onStepEnd: onStepEnd,
        onError: onError,
        onFinish: onFinish,
        internalOptions: internalOptions,
        settings: settings
    )
}

// MARK: - Internal implementation

/// One `streamObject` call: starts the model stream and owns its consumption.
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
private struct StreamObjectRun<ResultValue: Sendable, PartialValue: Sendable, ElementStream>: @unchecked Sendable {
    let model: any LanguageModelV4
    let output: GenerateObjectOutputSpec<ResultValue, PartialValue, ElementStream>
    let repairText: RepairTextFunction?
    let dispatcher: TelemetryDispatcher
    let download: DownloadFunction?
    let providerOptions: ProviderOptions?
    let onStart: GenerateObjectCallback<GenerateObjectStartEvent>?
    let onStepStart: GenerateObjectCallback<GenerateObjectStepStartEvent>?
    let onStepEnd: GenerateObjectCallback<GenerateObjectStepEndEvent>?
    let errorHandler: StreamObjectOnErrorCallback
    let onFinish: GenerateObjectCallback<GenerateObjectEndEvent<ResultValue>>?
    let internalOptions: GenerateObjectInternalOptions
    let settings: CallSettings
    let system: String?
    let prompt: String?
    let messages: [ModelMessage]?
    let result: StreamObjectResult<PartialValue, ResultValue, ElementStream>
    let callId: String

    func start() async throws {
        let preparedRetries = try prepareRetries(
            maxRetries: settings.maxRetries,
            abortSignal: settings.abortSignal
        )

        let callSettings = try prepareCallSettings(
            maxOutputTokens: settings.maxOutputTokens,
            temperature: settings.temperature,
            topP: settings.topP,
            topK: settings.topK,
            presencePenalty: settings.presencePenalty,
            frequencyPenalty: settings.frequencyPenalty,
            stopSequences: settings.stopSequences,
            seed: settings.seed,
            reasoning: settings.reasoning
        )

        let jsonSchema = try await output.strategy.jsonSchema()

        let startEvent = GenerateObjectStartEvent(
            callId: callId,
            operationId: "ai.streamObject",
            provider: model.provider,
            modelId: model.modelId,
            system: system.map(Instructions.text),
            prompt: prompt.map(PromptContent.text),
            messages: messages,
            maxOutputTokens: callSettings.maxOutputTokens,
            temperature: callSettings.temperature,
            topP: callSettings.topP,
            topK: callSettings.topK,
            presencePenalty: callSettings.presencePenalty,
            frequencyPenalty: callSettings.frequencyPenalty,
            seed: callSettings.seed,
            maxRetries: preparedRetries.maxRetries,
            headers: settings.headers,
            providerOptions: providerOptions,
            output: output.kind.rawValue,
            schema: jsonSchema,
            schemaName: output.schemaName,
            schemaDescription: output.schemaDescription
        )
        await notify(
            invoke(onStart, with: startEvent),
            { await dispatcher.onStart(.generateObject(startEvent)) }
        )

        let standardizedPrompt = try standardizePrompt(makeGenerateObjectPrompt(
            system: system,
            prompt: prompt,
            messages: messages
        ))
        let promptMessages = try await convertToLanguageModelV4Prompt(
            prompt: standardizedPrompt,
            supportedUrls: try await model.supportedUrls,
            download: download
        )

        let stepStartEvent = GenerateObjectStepStartEvent(
            callId: callId,
            provider: model.provider,
            modelId: model.modelId,
            providerOptions: providerOptions,
            headers: settings.headers,
            promptMessages: promptMessages
        )
        await notify(
            invoke(onStepStart, with: stepStartEvent),
            { await dispatcher.onObjectStepStart(stepStartEvent) }
        )

        // A schema-less output still asks for JSON, as upstream does.
        let options = LanguageModelV4CallOptions(
            prompt: promptMessages,
            maxOutputTokens: callSettings.maxOutputTokens,
            temperature: callSettings.temperature,
            stopSequences: callSettings.stopSequences,
            topP: callSettings.topP,
            topK: callSettings.topK,
            presencePenalty: callSettings.presencePenalty,
            frequencyPenalty: callSettings.frequencyPenalty,
            responseFormat: .json(
                schema: jsonSchema,
                name: output.schemaName,
                description: output.schemaDescription
            ),
            seed: callSettings.seed,
            includeRawChunks: false,
            abortSignal: settings.abortSignal,
            headers: settings.headers,
            reasoning: callSettings.reasoning,
            providerOptions: providerOptions
        )

        let startTimestampMs = internalOptions.now()
        let streamResult = try await preparedRetries.retry.call {
            try await model.doStream(options: options)
        }
        let request = convertGenerateObjectRequestMetadata(streamResult.request)
        result.resolveRequest(request)

        do {
            try await consume(streamResult, request: request, startTimestampMs: startTimestampMs)
        } catch {
            let normalized = (wrapGatewayError(error) as? Error) ?? error
            result.rejectPending(normalized)
            await dispatcher.onError(callId: callId, error: normalized)
            await errorHandler(StreamObjectErrorEvent(error: normalized))
            await result.endStream(error: normalized)
        }
    }

    private func consume(
        _ streamResult: LanguageModelV4StreamResult,
        request: LanguageModelRequestMetadata,
        startTimestampMs: Double
    ) async throws {
        var accumulatedText = ""
        var pendingDelta = ""
        var latestJSON: JSONValue?
        var latestPartial: PartialValue?
        var isFirstDelta = true
        var isFirstChunk = true
        var msToFirstChunk: Double?

        var warnings: [CallWarning]?
        var usage = LanguageModelUsage()
        var providerMetadata: ProviderMetadata?
        var finishReason: FinishReason?
        var terminalError: (any Error)?
        var parseError: (any Error)?
        var object: ResultValue?

        var responseId = internalOptions.generateId()
        var responseTimestamp = internalOptions.currentDate()
        var responseModelId = model.modelId
        let responseHeaders = streamResult.response?.headers

        func responseMetadata() -> LanguageModelResponseMetadata {
            LanguageModelResponseMetadata(
                id: responseId,
                timestamp: responseTimestamp,
                modelId: responseModelId,
                headers: responseHeaders
            )
        }

        for try await part in streamResult.stream {
            if case .streamStart(let streamWarnings) = part {
                warnings = streamWarnings
                continue
            }

            if isFirstChunk {
                isFirstChunk = false
                msToFirstChunk = internalOptions.now() - startTimestampMs
            }

            switch part {
            case .responseMetadata(let id, let modelId, let timestamp):
                if let id { responseId = id }
                if let modelId { responseModelId = modelId }
                if let timestamp { responseTimestamp = timestamp }

            case .textDelta(_, let delta, _):
                accumulatedText.append(delta)
                pendingDelta.append(delta)

                let parseResult = await parsePartialJson(accumulatedText)
                guard let currentJSON = parseResult.value, latestJSON != currentJSON else { continue }

                let validation = await output.strategy.validatePartial(
                    currentJSON,
                    pendingDelta,
                    isFirstDelta,
                    parseResult.state == .successfulParse,
                    latestPartial
                )
                guard case let .success(validationResult) = validation else { continue }
                if let latestPartial, isDeepEqualData(validationResult.partial, latestPartial) { continue }

                latestJSON = currentJSON
                latestPartial = validationResult.partial
                isFirstDelta = false

                await result.publish(.object(validationResult.partial))
                if !validationResult.textDelta.isEmpty {
                    await result.publish(.textDelta(validationResult.textDelta))
                }
                pendingDelta = ""

            case .error(let payload):
                let error = (wrapGatewayError(normalizeStreamProviderError(payload)) as? Error)
                    ?? normalizeStreamProviderError(payload)
                if terminalError == nil {
                    terminalError = error
                    finishReason = .error
                    result.rejectPending(error)
                }
                await result.publish(.error(AnySendableError(error)))
                await errorHandler(StreamObjectErrorEvent(error: error))

            case .finish(let reason, let usageValue, let metadata):
                if !pendingDelta.isEmpty {
                    await result.publish(.textDelta(pendingDelta))
                    pendingDelta = ""
                }

                finishReason = terminalError == nil ? reason.unified : .error
                usage = asLanguageModelUsage(usageValue)
                providerMetadata = metadata

                await result.publish(.finish(GenerateObjectStreamFinish(
                    finishReason: finishReason ?? .other,
                    usage: usage,
                    response: responseMetadata(),
                    providerMetadata: providerMetadata
                )))

                logWarnings((warnings ?? []).map { Warning.languageModel($0) })

                guard terminalError == nil else { break }

                result.resolveUsage(usage)
                result.resolveProviderMetadata(providerMetadata)
                result.resolveWarnings(warnings)
                result.resolveResponse(responseMetadata())
                result.resolveFinishReason(finishReason ?? .other)

                do {
                    let value = try await parseAndValidateObjectResultWithRepair(
                        text: accumulatedText,
                        strategy: output.strategy,
                        repairText: repairText,
                        context: GenerateObjectValidationContext(
                            text: accumulatedText,
                            response: responseMetadata(),
                            usage: usage,
                            finishReason: finishReason ?? .other
                        )
                    )
                    object = value
                    result.resolveObject(value)
                } catch {
                    parseError = error
                    result.rejectObject(error)
                }

            case .streamStart, .raw, .textStart, .textEnd, .reasoningStart, .reasoningDelta, .reasoningEnd,
                 .toolInputStart, .toolInputDelta, .toolInputEnd, .toolApprovalRequest, .toolCall,
                 .toolResult, .custom, .file, .reasoningFile, .source:
                continue
            }
        }

        if finishReason == nil {
            result.rejectPending(NoObjectGeneratedError(
                message: "No object generated: the stream ended without a finish part.",
                response: responseMetadata(),
                usage: usage,
                finishReason: .other
            ))
        }

        let stepEndEvent = GenerateObjectStepEndEvent(
            callId: callId,
            provider: model.provider,
            modelId: model.modelId,
            finishReason: finishReason ?? .other,
            usage: usage,
            objectText: accumulatedText,
            reasoning: nil,
            warnings: warnings,
            request: request,
            response: responseMetadata(),
            providerMetadata: providerMetadata,
            msToFirstChunk: msToFirstChunk
        )
        await notify(
            invoke(onStepEnd, with: stepEndEvent),
            { await dispatcher.onObjectStepEnd(stepEndEvent) }
        )

        let endEvent = GenerateObjectEndEvent<ResultValue>(
            callId: callId,
            object: object,
            error: terminalError ?? parseError,
            reasoning: nil,
            finishReason: finishReason ?? .other,
            usage: usage,
            warnings: warnings,
            request: request,
            response: responseMetadata(),
            providerMetadata: providerMetadata
        )
        await notify(
            invoke(onFinish, with: endEvent),
            { await dispatcher.onEnd(.generateObject(endEvent.json)) }
        )

        await result.endStream()
    }
}

// MARK: - Callbacks

public struct StreamObjectErrorEvent: Sendable {
    public let error: Error

    public init(error: Error) {
        self.error = error
    }
}

public typealias StreamObjectOnErrorCallback = @Sendable (StreamObjectErrorEvent) async -> Void
