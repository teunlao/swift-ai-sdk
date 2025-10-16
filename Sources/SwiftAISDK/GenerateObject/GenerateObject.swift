import Foundation
import AISDKProvider
import AISDKProviderUtils

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func generateObject<ResultValue, PartialValue, ElementStream>(
    model modelArg: LanguageModel,
    output: GenerateObjectOutputSpec<ResultValue, PartialValue, ElementStream>,
    system: String? = nil,
    prompt: String? = nil,
    messages: [ModelMessage]? = nil,
    experimentalRepairText repairText: RepairTextFunction? = nil,
    experimentalTelemetry telemetry: TelemetrySettings? = nil,
    experimentalDownload download: DownloadFunction? = nil,
    providerOptions: ProviderOptions? = nil,
    internalOptions _internal: GenerateObjectInternalOptions = GenerateObjectInternalOptions(),
    settings: CallSettings = CallSettings()
) async throws -> GenerateObjectResult<ResultValue> {
    let resolvedModel = try resolveLanguageModel(modelArg)

    _ = telemetry // reserved for future telemetry integration

    try validateObjectGenerationInput(
        output: output.kind,
        hasSchema: output.kind == .object || output.kind == .array,
        schemaName: output.schemaName,
        schemaDescription: output.schemaDescription,
        enumValues: output.enumValues
    )

    let retries = try prepareRetries(
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

    let headersWithUserAgent = withUserAgentSuffix(
        settings.headers ?? [:],
        "ai/\(VERSION)"
    )

    let promptInput: Prompt
    if let promptText = prompt {
        if messages != nil {
            throw InvalidPromptError(
                prompt: "Prompt(system: \(system ?? "nil"), prompt: \(promptText), messages: provided)",
                message: "Provide either `prompt` or `messages`, not both."
            )
        }
        promptInput = Prompt.text(promptText, system: system)
    } else if let messageList = messages {
        promptInput = Prompt.messages(messageList, system: system)
    } else {
        throw InvalidPromptError(
            prompt: "Prompt(system: \(system ?? "nil"))",
            message: "Either `prompt` or `messages` must be provided."
        )
    }

    let standardizedPrompt = try standardizePrompt(promptInput)

    let promptMessages = try await convertToLanguageModelPrompt(
        prompt: standardizedPrompt,
        supportedUrls: try await resolvedModel.supportedUrls,
        download: download
    )

    let jsonSchema = try await output.strategy.jsonSchema()

    do {
        let generateResult = try await retries.retry.call {
            try await resolvedModel.doGenerate(
                options: LanguageModelV3CallOptions(
                    prompt: promptMessages,
                    maxOutputTokens: preparedCallSettings.maxOutputTokens,
                    temperature: preparedCallSettings.temperature,
                    stopSequences: preparedCallSettings.stopSequences,
                    topP: preparedCallSettings.topP,
                    topK: preparedCallSettings.topK,
                    presencePenalty: preparedCallSettings.presencePenalty,
                    frequencyPenalty: preparedCallSettings.frequencyPenalty,
                    responseFormat: .json(
                        schema: jsonSchema,
                        name: output.schemaName,
                        description: output.schemaDescription
                    ),
                    seed: preparedCallSettings.seed,
                    abortSignal: settings.abortSignal,
                    headers: headersWithUserAgent,
                    providerOptions: providerOptions
                )
            )
        }

        guard let text = extractTextContent(content: generateResult.content) else {
            throw NoObjectGeneratedError(
                message: "No object generated: the model did not return a response.",
                response: LanguageModelResponseMetadata(
                    id: generateResult.response?.id ?? _internal.generateId(),
                    timestamp: generateResult.response?.timestamp ?? _internal.currentDate(),
                    modelId: generateResult.response?.modelId ?? resolvedModel.modelId,
                    headers: generateResult.response?.headers
                ),
                usage: generateResult.usage,
                finishReason: generateResult.finishReason
            )
        }

        let reasoning = extractReasoningContent(content: generateResult.content)

        let responseMetadata = LanguageModelResponseMetadataWithBody(
            id: generateResult.response?.id ?? _internal.generateId(),
            timestamp: generateResult.response?.timestamp ?? _internal.currentDate(),
            modelId: generateResult.response?.modelId ?? resolvedModel.modelId,
            headers: generateResult.response?.headers,
            body: convertResponseBody(generateResult.response?.body)
        )

        let context = GenerateObjectValidationContext(
            text: text,
            response: LanguageModelResponseMetadata(
                id: responseMetadata.id,
                timestamp: responseMetadata.timestamp,
                modelId: responseMetadata.modelId,
                headers: responseMetadata.headers
            ),
            usage: generateResult.usage,
            finishReason: generateResult.finishReason
        )

        let parsedObject = try await parseAndValidateObjectResultWithRepair(
            text: text,
            strategy: output.strategy,
            repairText: repairText,
            context: context
        )

        logWarnings(generateResult.warnings.map { Warning.languageModel($0) })

        return GenerateObjectResult(
            object: parsedObject,
            reasoning: reasoning,
            finishReason: generateResult.finishReason,
            usage: generateResult.usage,
            warnings: generateResult.warnings,
            request: convertRequestMetadata(generateResult.request),
            response: responseMetadata,
            providerMetadata: generateResult.providerMetadata
        )
    } catch {
        throw (wrapGatewayError(error) as? Error) ?? error
    }
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
    experimentalRepairText repairText: RepairTextFunction? = nil,
    experimentalTelemetry telemetry: TelemetrySettings? = nil,
    experimentalDownload download: DownloadFunction? = nil,
    providerOptions: ProviderOptions? = nil,
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
        experimentalRepairText: repairText,
        experimentalTelemetry: telemetry,
        experimentalDownload: download,
        providerOptions: providerOptions,
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
    experimentalRepairText repairText: RepairTextFunction? = nil,
    experimentalTelemetry telemetry: TelemetrySettings? = nil,
    experimentalDownload download: DownloadFunction? = nil,
    providerOptions: ProviderOptions? = nil,
    internalOptions: GenerateObjectInternalOptions = GenerateObjectInternalOptions(),
    settings: CallSettings = CallSettings()
) async throws -> GenerateObjectResult<JSONValue> {
    try await generateObject(
        model: model,
        output: GenerateObjectOutput.noSchema(),
        system: system,
        prompt: prompt,
        messages: messages,
        experimentalRepairText: repairText,
        experimentalTelemetry: telemetry,
        experimentalDownload: download,
        providerOptions: providerOptions,
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
    experimentalRepairText repairText: RepairTextFunction? = nil,
    experimentalTelemetry telemetry: TelemetrySettings? = nil,
    experimentalDownload download: DownloadFunction? = nil,
    providerOptions: ProviderOptions? = nil,
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
        experimentalRepairText: repairText,
        experimentalTelemetry: telemetry,
        experimentalDownload: download,
        providerOptions: providerOptions,
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
    experimentalRepairText repairText: RepairTextFunction? = nil,
    experimentalTelemetry telemetry: TelemetrySettings? = nil,
    experimentalDownload download: DownloadFunction? = nil,
    providerOptions: ProviderOptions? = nil,
    internalOptions: GenerateObjectInternalOptions = GenerateObjectInternalOptions(),
    settings: CallSettings = CallSettings()
) async throws -> GenerateObjectResult<String> {
    try await generateObject(
        model: model,
        output: GenerateObjectOutput.enumeration(values: values),
        system: system,
        prompt: prompt,
        messages: messages,
        experimentalRepairText: repairText,
        experimentalTelemetry: telemetry,
        experimentalDownload: download,
        providerOptions: providerOptions,
        internalOptions: internalOptions,
        settings: settings
    )
}

private func convertRequestMetadata(_ info: LanguageModelV3RequestInfo?) -> LanguageModelRequestMetadata {
    guard let rawBody = info?.body else {
        return LanguageModelRequestMetadata()
    }
    if let jsonValue = try? jsonValue(from: rawBody) {
        return LanguageModelRequestMetadata(body: jsonValue)
    }
    return LanguageModelRequestMetadata()
}

private func convertResponseBody(_ body: Any?) -> JSONValue? {
    guard let body else { return nil }
    if let jsonValue = body as? JSONValue {
        return jsonValue
    }
    return try? jsonValue(from: body)
}
