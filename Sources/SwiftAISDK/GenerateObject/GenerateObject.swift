import Foundation
import AISDKProvider
import AISDKProviderUtils
import AISDKJSONSchema

/**
 Generates a structured object for a prompt and schema, without streaming.

 Port of `@ai-sdk/ai/src/generate-object/generate-object.ts`. Callbacks run
 concurrently with the telemetry integrations; errors they throw are ignored.
 */
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func generateObject<ResultValue, PartialValue, ElementStream>(
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
    onFinish: GenerateObjectCallback<GenerateObjectEndEvent<ResultValue>>? = nil,
    internalOptions _internal: GenerateObjectInternalOptions = GenerateObjectInternalOptions(),
    settings: CallSettings = CallSettings()
) async throws -> GenerateObjectResult<ResultValue> {
    let model = try resolveLanguageModelV4(modelArg)

    try validateObjectGenerationInput(
        output: output.kind,
        hasSchema: output.kind == .object || output.kind == .array,
        schemaName: output.schemaName,
        schemaDescription: output.schemaDescription,
        enumValues: output.enumValues
    )

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

    let headersWithUserAgent = withUserAgentSuffix(
        settings.headers ?? [:],
        "ai/\(VERSION)"
    )

    let dispatcher = TelemetryDispatcher(telemetry: telemetry)
    let jsonSchema = try await output.strategy.jsonSchema()
    let callId = _internal.generateId()

    let startEvent = GenerateObjectStartEvent(
        callId: callId,
        operationId: "ai.generateObject",
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
        headers: headersWithUserAgent,
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

    do {
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
            headers: headersWithUserAgent,
            promptMessages: promptMessages
        )
        await notify(
            invoke(onStepStart, with: stepStartEvent),
            { await dispatcher.onObjectStepStart(stepStartEvent) }
        )

        let generateResult = try await preparedRetries.retry.call {
            try await model.doGenerate(
                options: LanguageModelV4CallOptions(
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
                    abortSignal: settings.abortSignal,
                    headers: headersWithUserAgent,
                    reasoning: callSettings.reasoning,
                    providerOptions: providerOptions
                )
            )
        }

        let response = LanguageModelResponseMetadataWithBody(
            id: generateResult.response?.id ?? _internal.generateId(),
            timestamp: generateResult.response?.timestamp ?? _internal.currentDate(),
            modelId: generateResult.response?.modelId ?? model.modelId,
            headers: generateResult.response?.headers,
            body: convertGenerateObjectResponseBody(generateResult.response?.body)
        )
        let responseMetadata = LanguageModelResponseMetadata(
            id: response.id,
            timestamp: response.timestamp,
            modelId: response.modelId,
            headers: response.headers
        )
        let finishReason = generateResult.finishReason.unified
        let usage = asLanguageModelUsage(generateResult.usage)

        guard let text = extractTextContent(content: generateResult.content) else {
            throw NoObjectGeneratedError(
                message: "No object generated: the model did not return a response.",
                response: responseMetadata,
                usage: usage,
                finishReason: finishReason
            )
        }

        let reasoning = extractReasoningContent(content: generateResult.content)
        let warnings = generateResult.warnings
        let request = convertGenerateObjectRequestMetadata(generateResult.request)

        logWarnings((warnings ?? []).map { Warning.languageModel($0) })

        let stepEndEvent = GenerateObjectStepEndEvent(
            callId: callId,
            provider: model.provider,
            modelId: model.modelId,
            finishReason: finishReason,
            usage: usage,
            objectText: text,
            reasoning: reasoning,
            warnings: warnings,
            request: request,
            response: responseMetadata,
            responseBody: response.body,
            providerMetadata: generateResult.providerMetadata,
            msToFirstChunk: nil
        )
        await notify(
            invoke(onStepEnd, with: stepEndEvent),
            { await dispatcher.onObjectStepEnd(stepEndEvent) }
        )

        let object = try await parseAndValidateObjectResultWithRepair(
            text: text,
            strategy: output.strategy,
            repairText: repairText,
            context: GenerateObjectValidationContext(
                text: text,
                response: responseMetadata,
                usage: usage,
                finishReason: finishReason
            )
        )

        let endEvent = GenerateObjectEndEvent<ResultValue>(
            callId: callId,
            object: object,
            error: nil,
            reasoning: reasoning,
            finishReason: finishReason,
            usage: usage,
            warnings: warnings,
            request: request,
            response: responseMetadata,
            providerMetadata: generateResult.providerMetadata
        )
        await notify(
            invoke(onFinish, with: endEvent),
            { await dispatcher.onEnd(.generateObject(endEvent.json)) }
        )

        return GenerateObjectResult(
            object: object,
            reasoning: reasoning,
            finishReason: finishReason,
            usage: usage,
            warnings: warnings,
            request: request,
            response: response,
            providerMetadata: generateResult.providerMetadata
        )
    } catch {
        await dispatcher.onError(callId: callId, error: error)
        throw (wrapGatewayError(error) as? Error) ?? error
    }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func generateObject<ObjectResult: Codable & Sendable>(
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
    onFinish: GenerateObjectCallback<GenerateObjectEndEvent<ObjectResult>>? = nil,
    internalOptions: GenerateObjectInternalOptions = GenerateObjectInternalOptions(),
    settings: CallSettings = CallSettings()
) async throws -> GenerateObjectResult<ObjectResult> {
    try await generateObject(
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
        onFinish: onFinish,
        internalOptions: internalOptions,
        settings: settings
    )
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func generateObject<ObjectResult>(
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
    onFinish: GenerateObjectCallback<GenerateObjectEndEvent<ObjectResult>>? = nil,
    internalOptions: GenerateObjectInternalOptions = GenerateObjectInternalOptions(),
    settings: CallSettings = CallSettings()
) async throws -> GenerateObjectResult<ObjectResult> {
    try await generateObject(
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
        onFinish: onFinish,
        internalOptions: internalOptions,
        settings: settings
    )
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func generateObjectNoSchema(
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
    onFinish: GenerateObjectCallback<GenerateObjectEndEvent<JSONValue>>? = nil,
    internalOptions: GenerateObjectInternalOptions = GenerateObjectInternalOptions(),
    settings: CallSettings = CallSettings()
) async throws -> GenerateObjectResult<JSONValue> {
    try await generateObject(
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
        onFinish: onFinish,
        internalOptions: internalOptions,
        settings: settings
    )
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func generateObjectArray<ElementResult: Codable & Sendable>(
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
    onFinish: GenerateObjectCallback<GenerateObjectEndEvent<[ElementResult]>>? = nil,
    internalOptions: GenerateObjectInternalOptions = GenerateObjectInternalOptions(),
    settings: CallSettings = CallSettings()
) async throws -> GenerateObjectResult<[ElementResult]> {
    try await generateObjectArray(
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
        onFinish: onFinish,
        internalOptions: internalOptions,
        settings: settings
    )
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func generateObjectArray<ElementResult>(
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
    onFinish: GenerateObjectCallback<GenerateObjectEndEvent<[ElementResult]>>? = nil,
    internalOptions: GenerateObjectInternalOptions = GenerateObjectInternalOptions(),
    settings: CallSettings = CallSettings()
) async throws -> GenerateObjectResult<[ElementResult]> {
    try await generateObject(
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
        onFinish: onFinish,
        internalOptions: internalOptions,
        settings: settings
    )
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func generateObjectEnum(
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
    onFinish: GenerateObjectCallback<GenerateObjectEndEvent<String>>? = nil,
    internalOptions: GenerateObjectInternalOptions = GenerateObjectInternalOptions(),
    settings: CallSettings = CallSettings()
) async throws -> GenerateObjectResult<String> {
    try await generateObject(
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
        onFinish: onFinish,
        internalOptions: internalOptions,
        settings: settings
    )
}
