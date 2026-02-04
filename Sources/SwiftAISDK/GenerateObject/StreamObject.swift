import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Streams an object (JSON/array/enum/no-schema) from a language model with partial updates and telemetry.

 Port of `@ai-sdk/ai/src/generate-object/stream-object.ts`.
 */
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func streamObject<ResultValue, PartialValue, ElementStream>(
    model modelArg: LanguageModel,
    output: GenerateObjectOutputSpec<ResultValue, PartialValue, ElementStream>,
    system: String? = nil,
    prompt: String? = nil,
    messages: [ModelMessage]? = nil,
    experimentalRepairText repairText: RepairTextFunction? = nil,
    experimentalTelemetry telemetry: TelemetrySettings? = nil,
    experimentalDownload download: DownloadFunction? = nil,
    providerOptions: ProviderOptions? = nil,
    onError: StreamObjectOnErrorCallback? = nil,
    onFinish: StreamObjectOnFinishCallback<ResultValue>? = nil,
    internalOptions _internal: GenerateObjectInternalOptions = GenerateObjectInternalOptions(),
    settings: CallSettings = CallSettings()
) throws -> StreamObjectResult<PartialValue, ResultValue, ElementStream> {
    let resolvedModel = try resolveLanguageModel(modelArg)

    let hasSchema = output.kind == .object || output.kind == .array
    try validateObjectGenerationInput(
        output: output.kind,
        hasSchema: hasSchema,
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

    Task {
        do {
            try await runStreamObject(
                model: resolvedModel,
                output: output,
                repairText: repairText,
                telemetry: telemetry,
                download: download,
                providerOptions: providerOptions,
                errorHandler: errorHandler,
                onFinish: onFinish,
                internalOptions: _internal,
                settings: settings,
                system: system,
                prompt: prompt,
                messages: messages,
                result: result
            )
        } catch {
            let normalized = (wrapGatewayError(error) as? Error) ?? error
            await errorHandler(StreamObjectErrorEvent(error: normalized))
            result.rejectObject(normalized)
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
    experimentalRepairText repairText: RepairTextFunction? = nil,
    experimentalTelemetry telemetry: TelemetrySettings? = nil,
    experimentalDownload download: DownloadFunction? = nil,
    providerOptions: ProviderOptions? = nil,
    onError: StreamObjectOnErrorCallback? = nil,
    onFinish: StreamObjectOnFinishCallback<ObjectResult>? = nil,
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
        experimentalRepairText: repairText,
        experimentalTelemetry: telemetry,
        experimentalDownload: download,
        providerOptions: providerOptions,
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
    experimentalRepairText repairText: RepairTextFunction? = nil,
    experimentalTelemetry telemetry: TelemetrySettings? = nil,
    experimentalDownload download: DownloadFunction? = nil,
    providerOptions: ProviderOptions? = nil,
    onError: StreamObjectOnErrorCallback? = nil,
    onFinish: StreamObjectOnFinishCallback<ObjectResult>? = nil,
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
        experimentalRepairText: repairText,
        experimentalTelemetry: telemetry,
        experimentalDownload: download,
        providerOptions: providerOptions,
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
    experimentalRepairText repairText: RepairTextFunction? = nil,
    experimentalTelemetry telemetry: TelemetrySettings? = nil,
    experimentalDownload download: DownloadFunction? = nil,
    providerOptions: ProviderOptions? = nil,
    onError: StreamObjectOnErrorCallback? = nil,
    onFinish: StreamObjectOnFinishCallback<JSONValue>? = nil,
    internalOptions: GenerateObjectInternalOptions = GenerateObjectInternalOptions(),
    settings: CallSettings = CallSettings()
) throws -> StreamObjectResult<JSONValue, JSONValue, Never> {
    try streamObject(
        model: model,
        output: GenerateObjectOutput.noSchema(),
        system: system,
        prompt: prompt,
        messages: messages,
        experimentalRepairText: repairText,
        experimentalTelemetry: telemetry,
        experimentalDownload: download,
        providerOptions: providerOptions,
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
    experimentalRepairText repairText: RepairTextFunction? = nil,
    experimentalTelemetry telemetry: TelemetrySettings? = nil,
    experimentalDownload download: DownloadFunction? = nil,
    providerOptions: ProviderOptions? = nil,
    onError: StreamObjectOnErrorCallback? = nil,
    onFinish: StreamObjectOnFinishCallback<[ElementResult]>? = nil,
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
        experimentalRepairText: repairText,
        experimentalTelemetry: telemetry,
        experimentalDownload: download,
        providerOptions: providerOptions,
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
    experimentalRepairText repairText: RepairTextFunction? = nil,
    experimentalTelemetry telemetry: TelemetrySettings? = nil,
    experimentalDownload download: DownloadFunction? = nil,
    providerOptions: ProviderOptions? = nil,
    onError: StreamObjectOnErrorCallback? = nil,
    onFinish: StreamObjectOnFinishCallback<[ElementResult]>? = nil,
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
        experimentalRepairText: repairText,
        experimentalTelemetry: telemetry,
        experimentalDownload: download,
        providerOptions: providerOptions,
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
    experimentalRepairText repairText: RepairTextFunction? = nil,
    experimentalTelemetry telemetry: TelemetrySettings? = nil,
    experimentalDownload download: DownloadFunction? = nil,
    providerOptions: ProviderOptions? = nil,
    onError: StreamObjectOnErrorCallback? = nil,
    onFinish: StreamObjectOnFinishCallback<String>? = nil,
    internalOptions: GenerateObjectInternalOptions = GenerateObjectInternalOptions(),
    settings: CallSettings = CallSettings()
) throws -> StreamObjectResult<String, String, Never> {
    try streamObject(
        model: model,
        output: GenerateObjectOutput.enumeration(values: values),
        system: system,
        prompt: prompt,
        messages: messages,
        experimentalRepairText: repairText,
        experimentalTelemetry: telemetry,
        experimentalDownload: download,
        providerOptions: providerOptions,
        onError: onError,
        onFinish: onFinish,
        internalOptions: internalOptions,
        settings: settings
    )
}

// MARK: - Internal implementation

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
private func runStreamObject<ResultValue, PartialValue, ElementStream>(
    model: any LanguageModelV3,
    output: GenerateObjectOutputSpec<ResultValue, PartialValue, ElementStream>,
    repairText: RepairTextFunction?,
    telemetry: TelemetrySettings?,
    download: DownloadFunction?,
    providerOptions: ProviderOptions?,
    errorHandler: StreamObjectOnErrorCallback,
    onFinish: StreamObjectOnFinishCallback<ResultValue>?,
    internalOptions: GenerateObjectInternalOptions,
    settings: CallSettings,
    system: String?,
    prompt: String?,
    messages: [ModelMessage]?,
    result: StreamObjectResult<PartialValue, ResultValue, ElementStream>
) async throws {
    let promptInput = try makeGenerateObjectPrompt(
        system: system,
        prompt: prompt,
        messages: messages
    )

    let preparedRetries = try prepareRetries(
        maxRetries: settings.maxRetries,
        abortSignal: settings.abortSignal
    )

    let preparedCallSettings = try prepareCallSettings(
        maxOutputTokens: settings.maxOutputTokens,
        temperature: settings.temperature,
        topP: settings.topP,
        topK: settings.topK,
        presencePenalty: settings.presencePenalty,
        frequencyPenalty: settings.frequencyPenalty,
        stopSequences: settings.stopSequences,
        seed: settings.seed
    )

    var telemetryCallSettings = settings
    telemetryCallSettings.maxRetries = preparedRetries.maxRetries

    let baseTelemetryAttributes = getBaseTelemetryAttributes(
        model: TelemetryModelInfo(modelId: model.modelId, provider: model.provider),
        settings: telemetryCallSettings,
        telemetry: telemetry,
        headers: settings.headers
    )

    let tracer = getTracer(
        isEnabled: telemetry?.isEnabled ?? false,
        tracer: telemetry?.tracer
    )

    let standardizedPrompt = try standardizePrompt(promptInput)
    let promptMessages = try await convertToLanguageModelPrompt(
        prompt: standardizedPrompt,
        supportedUrls: try await model.supportedUrls,
        download: download
    )

    let jsonSchema = try await output.strategy.jsonSchema()

    let outerAttributes = try await selectTelemetryAttributes(
        telemetry: telemetry,
        attributes: makeGenerateObjectOuterTelemetryAttributes(
            telemetry: telemetry,
            baseAttributes: baseTelemetryAttributes,
            system: system,
            prompt: prompt,
            messages: messages,
            schema: jsonSchema,
            schemaName: output.schemaName,
            schemaDescription: output.schemaDescription,
            outputKind: output.kind
        )
    )

    try await recordSpan(
        name: "ai.streamObject",
        tracer: tracer,
        attributes: outerAttributes,
        fn: { rootSpan in
            let innerAttributes = try await selectTelemetryAttributes(
                telemetry: telemetry,
                attributes: makeGenerateObjectInnerTelemetryAttributes(
                    telemetry: telemetry,
                    baseAttributes: baseTelemetryAttributes,
                    promptMessages: promptMessages,
                    callSettings: preparedCallSettings,
                    model: model
                )
            )

            let execution = try await preparedRetries.retry.call {
                try await recordSpan(
                    name: "ai.streamObject.doStream",
                    tracer: tracer,
                    attributes: innerAttributes,
                    fn: { span in
                        let options = LanguageModelV3CallOptions(
                            prompt: promptMessages,
                            maxOutputTokens: preparedCallSettings.maxOutputTokens,
                            temperature: preparedCallSettings.temperature,
                            stopSequences: preparedCallSettings.stopSequences,
                            topP: preparedCallSettings.topP,
                            topK: preparedCallSettings.topK,
                            presencePenalty: preparedCallSettings.presencePenalty,
                            frequencyPenalty: preparedCallSettings.frequencyPenalty,
                            responseFormat: jsonSchema.map {
                                .json(
                                    schema: $0,
                                    name: output.schemaName,
                                    description: output.schemaDescription
                                )
                            },
                            seed: preparedCallSettings.seed,
                            abortSignal: settings.abortSignal,
                            headers: settings.headers,
                            providerOptions: providerOptions
                        )

                        let streamResult = try await model.doStream(options: options)
                        let requestMetadata = convertGenerateObjectRequestMetadata(streamResult.request)
                        result.resolveRequest(requestMetadata)

                        return StreamExecution(
                            span: span,
                            startTimestampMs: internalOptions.now(),
                            streamResult: streamResult
                        )
                    },
                    endWhenDone: false
                )
            }

            try await consumeStream(
                execution: execution,
                model: model,
                output: output,
                repairText: repairText,
                telemetry: telemetry,
                baseTelemetryAttributes: baseTelemetryAttributes,
                errorHandler: errorHandler,
                onFinish: onFinish,
                internalOptions: internalOptions,
                result: result,
                rootSpan: rootSpan
            )
        },
        endWhenDone: false
    )
}

private struct StreamExecution: Sendable {
    let span: any Span
    let startTimestampMs: Double
    let streamResult: LanguageModelV3StreamResult
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
private func consumeStream<ResultValue, PartialValue, ElementStream>(
    execution: StreamExecution,
    model: any LanguageModelV3,
    output: GenerateObjectOutputSpec<ResultValue, PartialValue, ElementStream>,
    repairText: RepairTextFunction?,
    telemetry: TelemetrySettings?,
    baseTelemetryAttributes: Attributes,
    errorHandler: StreamObjectOnErrorCallback,
    onFinish: StreamObjectOnFinishCallback<ResultValue>?,
    internalOptions: GenerateObjectInternalOptions,
    result: StreamObjectResult<PartialValue, ResultValue, ElementStream>,
    rootSpan: any Span
) async throws {
    let stream = execution.streamResult.stream
    let responseInfo = execution.streamResult.response

    var accumulatedText = ""
    var pendingDelta = ""

    var latestJSON: JSONValue?
    var latestPartial: PartialValue?
    var isFirstDelta = true

    var warnings: [CallWarning]?
    var usage = LanguageModelUsage()
    var providerMetadata: ProviderMetadata?
    var finishReason: FinishReason = .other
    var currentError: Error?

    var responseId = internalOptions.generateId()
    var responseTimestamp = internalOptions.currentDate()
    var responseModelId = model.modelId
    let responseHeaders = responseInfo?.headers

    var msToFirstChunkRecorded = false

    for try await part in stream {
        if Task.isCancelled { break }
        if !msToFirstChunkRecorded {
            msToFirstChunkRecorded = true
            let elapsed = internalOptions.now() - execution.startTimestampMs
            execution.span.addEvent(
                "ai.stream.firstChunk",
                attributes: makeStreamFirstChunkAttributes(msToFirstChunk: elapsed)
            )
            execution.span.setAttributes(makeStreamFirstChunkAttributes(msToFirstChunk: elapsed))
        }

        switch part {
        case .streamStart(let streamWarnings):
            warnings = streamWarnings

        case .responseMetadata(let id, let modelId, let timestamp):
            if let id { responseId = id }
            if let modelId { responseModelId = modelId }
            if let timestamp { responseTimestamp = timestamp }

        case .textDelta(_, let delta, _):
            // Accumulate raw deltas; we will emit a consolidated text chunk
            // only when a valid partial is produced by the strategy. This
            // matches upstream semantics where textStream surfaces the
            // strategy-computed deltaText, not every raw provider chunk.
            accumulatedText.append(delta)
            pendingDelta.append(delta)

            let parseResult = await parsePartialJson(accumulatedText)
            guard let currentJSON = parseResult.value else { continue }

            if latestJSON == currentJSON {
                continue
            }

            let validation = await output.strategy.validatePartial(
                currentJSON,
                pendingDelta,
                isFirstDelta,
                parseResult.state == .successfulParse,
                latestPartial
            )

            guard case let .success(validationResult) = validation else {
                continue
            }

            if let latestPartial,
               isDeepEqualData(validationResult.partial, latestPartial) {
                continue
            }

            latestJSON = currentJSON
            latestPartial = validationResult.partial
            isFirstDelta = false

            // Publish consolidated text delta produced by the strategy
            // (e.g., for arrays: brackets/commas; for objects: buffered raw).
            if !validationResult.textDelta.isEmpty {
                await result.publish(.textDelta(validationResult.textDelta))
            }

            pendingDelta = ""

            // Then publish the partial object snapshot.
            await result.publish(.object(validationResult.partial))

        case .finish(let reason, let usageValue, let metadata):
            // Flush any remaining buffered text that didn't result in a new
            // partial (e.g., closing braces), so the textStream reflects the
            // full JSON output as expected by upstream tests.
            if !pendingDelta.isEmpty {
                await result.publish(.textDelta(pendingDelta))
                pendingDelta = ""
            }

            finishReason = reason.unified
            usage = asLanguageModelUsage(usageValue)
            providerMetadata = metadata

       case .error(let errorJSON):
           currentError = jsonValueToError(errorJSON)
            await errorHandler(StreamObjectErrorEvent(error: currentError ?? StreamObjectUnknownError()))
            await result.publish(.error(AnySendableError(currentError ?? StreamObjectUnknownError())))

        case .raw,
             .textStart,
             .textEnd,
             .reasoningStart,
             .reasoningDelta,
             .reasoningEnd,
             .toolInputStart,
             .toolInputDelta,
             .toolInputEnd,
             .toolApprovalRequest,
             .toolCall,
             .toolResult,
             .file,
             .source:
            continue
        }
    }

    let responseMetadata = LanguageModelResponseMetadata(
        id: responseId,
        timestamp: responseTimestamp,
        modelId: responseModelId,
        headers: responseHeaders
    )

    let context = GenerateObjectValidationContext(
        text: accumulatedText,
        response: responseMetadata,
        usage: usage,
        finishReason: finishReason
    )

    var parsedObject: ResultValue?

    do {
        let value = try await parseAndValidateObjectResultWithRepair(
            text: accumulatedText,
            strategy: output.strategy,
            repairText: repairText,
            context: context
        )
        parsedObject = value
        result.resolveObject(value)
   } catch {
       currentError = error
       result.rejectObject(error)
        await errorHandler(StreamObjectErrorEvent(error: error))
        await result.publish(.error(AnySendableError(error)))
    }

    logWarnings((warnings ?? []).map { Warning.languageModel($0) })

    result.resolveUsage(usage)
    result.resolveProviderMetadata(providerMetadata)
    result.resolveWarnings(warnings)
    result.resolveResponse(responseMetadata)
    result.resolveFinishReason(finishReason)

    let finishEvent = GenerateObjectStreamFinish(
        finishReason: finishReason,
        usage: usage,
        response: responseMetadata,
        providerMetadata: providerMetadata
    )
    await result.publish(.finish(finishEvent))
    await result.endStream(error: currentError)

    let objectTelemetry = parsedObject.flatMap { encodeGenerateObjectTelemetryValue($0) }

    let responseAttributes = try await selectTelemetryAttributes(
        telemetry: telemetry,
        attributes: makeGenerateObjectResponseTelemetryAttributes(
            telemetry: telemetry,
            finishReason: finishReason,
            objectOutput: { objectTelemetry },
            responseId: responseMetadata.id,
            responseModelId: responseMetadata.modelId,
            responseTimestamp: responseMetadata.timestamp,
            providerMetadata: providerMetadata,
            usage: usage
        )
    )
    execution.span.setAttributes(responseAttributes)
    execution.span.end()

    let rootFinishAttributes = try await selectTelemetryAttributes(
        telemetry: telemetry,
        attributes: makeGenerateObjectRootFinishTelemetryAttributes(
            telemetry: telemetry,
            baseAttributes: baseTelemetryAttributes,
            usage: usage,
            providerMetadata: providerMetadata,
            finishReason: finishReason,
            objectOutput: { objectTelemetry }
        )
    )
    rootSpan.setAttributes(rootFinishAttributes)

    if let onFinish {
        let event = StreamObjectFinishEvent(
            usage: usage,
            object: parsedObject,
            error: currentError,
            response: responseMetadata,
            warnings: warnings,
            providerMetadata: providerMetadata,
            finishReason: finishReason
        )
        await onFinish(event)
    }

    rootSpan.end()

}

// MARK: - Helpers

public struct StreamObjectErrorEvent: Sendable {
    public let error: Error

    public init(error: Error) {
        self.error = error
    }
}

public struct StreamObjectFinishEvent<ResultValue>: Sendable where ResultValue: Sendable {
    public let usage: LanguageModelUsage
    public let object: ResultValue?
    public let error: Error?
    public let response: LanguageModelResponseMetadata
    public let warnings: [CallWarning]?
    public let providerMetadata: ProviderMetadata?
    public let finishReason: FinishReason

    public init(
        usage: LanguageModelUsage,
        object: ResultValue?,
        error: Error?,
        response: LanguageModelResponseMetadata,
        warnings: [CallWarning]?,
        providerMetadata: ProviderMetadata?,
        finishReason: FinishReason
    ) {
        self.usage = usage
        self.object = object
        self.error = error
        self.response = response
        self.warnings = warnings
        self.providerMetadata = providerMetadata
        self.finishReason = finishReason
    }
}

public typealias StreamObjectOnErrorCallback = @Sendable (StreamObjectErrorEvent) async -> Void
public typealias StreamObjectOnFinishCallback<ResultValue> = @Sendable (StreamObjectFinishEvent<ResultValue>) async -> Void

private func jsonValueToError(_ value: JSONValue) -> Error {
    if case let .string(message) = value {
        return StreamObjectUnknownError(message: message)
    }
    return StreamObjectUnknownError()
}

private struct StreamObjectUnknownError: Error {
    let message: String

    init(message: String = "Unknown stream error") {
        self.message = message
    }
}
