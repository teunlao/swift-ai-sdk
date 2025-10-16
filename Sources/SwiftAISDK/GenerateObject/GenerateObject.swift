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

    try validateObjectGenerationInput(
        output: output.kind,
        hasSchema: output.kind == .object || output.kind == .array,
        schemaName: output.schemaName,
        schemaDescription: output.schemaDescription,
        enumValues: output.enumValues
    )

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

    let headersWithUserAgent = withUserAgentSuffix(
        settings.headers ?? [:],
        "ai/\(VERSION)"
    )

    var telemetryCallSettings = settings
    telemetryCallSettings.maxRetries = preparedRetries.maxRetries

    let baseTelemetryAttributes = getBaseTelemetryAttributes(
        model: TelemetryModelInfo(modelId: resolvedModel.modelId, provider: resolvedModel.provider),
        settings: telemetryCallSettings,
        telemetry: telemetry,
        headers: headersWithUserAgent
    )

    let tracer = getTracer(
        isEnabled: telemetry?.isEnabled ?? false,
        tracer: telemetry?.tracer
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

    do {
        return try await recordSpan(
            name: "ai.generateObject",
            tracer: tracer,
            attributes: outerAttributes
        ) { rootSpan in
            let standardizedPrompt = try standardizePrompt(promptInput)

            let promptMessages = try await convertToLanguageModelPrompt(
                prompt: standardizedPrompt,
                supportedUrls: try await resolvedModel.supportedUrls,
                download: download
            )

            let innerAttributes = try await selectTelemetryAttributes(
                telemetry: telemetry,
                attributes: makeGenerateObjectInnerTelemetryAttributes(
                    telemetry: telemetry,
                    baseAttributes: baseTelemetryAttributes,
                    promptMessages: promptMessages,
                    callSettings: preparedCallSettings,
                    model: resolvedModel
                )
            )

            let intermediate = try await preparedRetries.retry.call {
                try await recordSpan(
                    name: "ai.generateObject.doGenerate",
                    tracer: tracer,
                    attributes: innerAttributes
                ) { span in
                    let generateResult = try await resolvedModel.doGenerate(
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

                    let responseId = generateResult.response?.id ?? _internal.generateId()
                    let responseTimestamp = generateResult.response?.timestamp ?? _internal.currentDate()
                    let responseModelId = generateResult.response?.modelId ?? resolvedModel.modelId
                    let responseHeaders = generateResult.response?.headers
                    let responseBody = convertGenerateObjectResponseBody(generateResult.response?.body)

                    guard let text = extractTextContent(content: generateResult.content) else {
                        throw NoObjectGeneratedError(
                            message: "No object generated: the model did not return a response.",
                            response: LanguageModelResponseMetadata(
                                id: responseId,
                                timestamp: responseTimestamp,
                                modelId: responseModelId,
                                headers: responseHeaders
                            ),
                            usage: generateResult.usage,
                            finishReason: generateResult.finishReason
                        )
                    }

                    let reasoning = extractReasoningContent(content: generateResult.content)

                    let responseMetadata = LanguageModelResponseMetadataWithBody(
                        id: responseId,
                        timestamp: responseTimestamp,
                        modelId: responseModelId,
                        headers: responseHeaders,
                        body: responseBody
                    )

                    let responseAttributes = try await selectTelemetryAttributes(
                        telemetry: telemetry,
                        attributes: makeGenerateObjectResponseTelemetryAttributes(
                            telemetry: telemetry,
                            finishReason: generateResult.finishReason,
                            objectOutput: { text },
                            responseId: responseId,
                            responseModelId: responseModelId,
                            responseTimestamp: responseTimestamp,
                            providerMetadata: generateResult.providerMetadata,
                            usage: generateResult.usage
                        )
                    )
                    span.setAttributes(responseAttributes)

                    return GenerateObjectIntermediateResult(
                        text: text,
                        reasoning: reasoning,
                        finishReason: generateResult.finishReason,
                        usage: generateResult.usage,
                        warnings: generateResult.warnings,
                        providerMetadata: generateResult.providerMetadata,
                        request: convertGenerateObjectRequestMetadata(generateResult.request),
                        response: responseMetadata
                    )
                }
            }

            logWarnings((intermediate.warnings ?? []).map { Warning.languageModel($0) })

            let responseMetadata = LanguageModelResponseMetadata(
                id: intermediate.response.id,
                timestamp: intermediate.response.timestamp,
                modelId: intermediate.response.modelId,
                headers: intermediate.response.headers
            )

            let context = GenerateObjectValidationContext(
                text: intermediate.text,
                response: responseMetadata,
                usage: intermediate.usage,
                finishReason: intermediate.finishReason
            )

            let parsedObject = try await parseAndValidateObjectResultWithRepair(
                text: intermediate.text,
                strategy: output.strategy,
                repairText: repairText,
                context: context
            )

            let objectTelemetry = encodeGenerateObjectTelemetryValue(parsedObject)

            let finishAttributes = try await selectTelemetryAttributes(
                telemetry: telemetry,
                attributes: makeGenerateObjectRootFinishTelemetryAttributes(
                    telemetry: telemetry,
                    baseAttributes: baseTelemetryAttributes,
                    usage: intermediate.usage,
                    providerMetadata: intermediate.providerMetadata,
                    finishReason: intermediate.finishReason,
                    objectOutput: { objectTelemetry }
                )
            )
            rootSpan.setAttributes(finishAttributes)

            return GenerateObjectResult(
                object: parsedObject,
                reasoning: intermediate.reasoning,
                finishReason: intermediate.finishReason,
                usage: intermediate.usage,
                warnings: intermediate.warnings,
                request: intermediate.request,
                response: intermediate.response,
                providerMetadata: intermediate.providerMetadata
            )
        }
    } catch {
        throw (wrapGatewayError(error) as? Error) ?? error
    }
}

private struct GenerateObjectIntermediateResult: Sendable {
    let text: String
    let reasoning: String?
    let finishReason: FinishReason
    let usage: LanguageModelUsage
    let warnings: [CallWarning]?
    let providerMetadata: ProviderMetadata?
    let request: LanguageModelRequestMetadata
    let response: LanguageModelResponseMetadataWithBody
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
