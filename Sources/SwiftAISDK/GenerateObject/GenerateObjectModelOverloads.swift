import Foundation
import AISDKProvider
import AISDKProviderUtils
import AISDKJSONSchema

// Overloads that take a provider model directly; Swift has no implicit conversion into `LanguageModel`.

// MARK: - generateObject overloads

/**
 Generate object with a LanguageModelV3 directly.

 Convenience overload that wraps the model in `LanguageModel.v3()`.
 */
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func generateObject<ObjectResult: Codable & Sendable>(
    model: any LanguageModelV3,
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
        model: .v3(model),
        schema: type,
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
    model: any LanguageModelV3,
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
        model: .v3(model),
        schema: schema,
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

// MARK: - generateObjectArray overloads

/**
 Generate object arrays with a LanguageModelV3 directly.

 Convenience overload that wraps the model in `LanguageModel.v3()`.
 */
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func generateObjectArray<ElementResult: Codable & Sendable>(
    model: any LanguageModelV3,
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
        model: .v3(model),
        schema: elementType,
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
    model: any LanguageModelV3,
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
    try await generateObjectArray(
        model: .v3(model),
        schema: schema,
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

// MARK: - generateObjectEnum overloads

/**
 Generate object enums with a LanguageModelV3 directly.

 Convenience overload that wraps the model in `LanguageModel.v3()`.
 */
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func generateObjectEnum(
    model: any LanguageModelV3,
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
    try await generateObjectEnum(
        model: .v3(model),
        values: values,
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

// MARK: - generateObjectNoSchema overloads

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func generateObjectNoSchema(
    model: any LanguageModelV3,
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
    try await generateObjectNoSchema(
        model: .v3(model),
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

// MARK: - streamObject overloads

/**
 Stream objects with a LanguageModelV3 directly.

 Convenience overload that wraps the model in `LanguageModel.v3()`.
 */
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func streamObject<ResultValue, PartialValue, ElementStream>(
    model: any LanguageModelV3,
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
    try streamObject(
        model: .v3(model),
        output: output,
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
        internalOptions: _internal,
        settings: settings
    )
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func streamObject<ObjectResult: Codable & Sendable>(
    model: any LanguageModelV3,
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
        model: .v3(model),
        schema: type,
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
    model: any LanguageModelV3,
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
        model: .v3(model),
        schema: schema,
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
public func streamObjectNoSchema(
    model: any LanguageModelV3,
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
    try streamObjectNoSchema(
        model: .v3(model),
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
    model: any LanguageModelV3,
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
        model: .v3(model),
        schema: elementType,
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
    model: any LanguageModelV3,
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
    try streamObjectArray(
        model: .v3(model),
        schema: schema,
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
public func streamObjectEnum(
    model: any LanguageModelV3,
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
    try streamObjectEnum(
        model: .v3(model),
        values: values,
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

// MARK: - generateObject V4 convenience

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func generateObject<ResultValue, PartialValue, ElementStream>(
    model: any LanguageModelV4,
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
    try await generateObject(
        model: .v4(model),
        output: output,
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
        internalOptions: _internal,
        settings: settings
    )
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func generateObject<ObjectResult: Codable & Sendable>(
    model: any LanguageModelV4,
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
        model: .v4(model),
        schema: type,
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
    model: any LanguageModelV4,
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
        model: .v4(model),
        schema: schema,
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
public func generateObjectArray<ElementResult: Codable & Sendable>(
    model: any LanguageModelV4,
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
        model: .v4(model),
        schema: elementType,
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
    model: any LanguageModelV4,
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
    try await generateObjectArray(
        model: .v4(model),
        schema: schema,
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
public func generateObjectEnum(
    model: any LanguageModelV4,
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
    try await generateObjectEnum(
        model: .v4(model),
        values: values,
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
    model: any LanguageModelV4,
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
    try await generateObjectNoSchema(
        model: .v4(model),
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

// MARK: - streamObject V4 convenience

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func streamObject<ResultValue, PartialValue, ElementStream>(
    model: any LanguageModelV4,
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
    try streamObject(
        model: .v4(model),
        output: output,
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
        internalOptions: _internal,
        settings: settings
    )
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func streamObject<ObjectResult: Codable & Sendable>(
    model: any LanguageModelV4,
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
        model: .v4(model),
        schema: type,
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
    model: any LanguageModelV4,
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
        model: .v4(model),
        schema: schema,
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
public func streamObjectNoSchema(
    model: any LanguageModelV4,
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
    try streamObjectNoSchema(
        model: .v4(model),
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
    model: any LanguageModelV4,
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
        model: .v4(model),
        schema: elementType,
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
    model: any LanguageModelV4,
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
    try streamObjectArray(
        model: .v4(model),
        schema: schema,
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
public func streamObjectEnum(
    model: any LanguageModelV4,
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
    try streamObjectEnum(
        model: .v4(model),
        values: values,
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
