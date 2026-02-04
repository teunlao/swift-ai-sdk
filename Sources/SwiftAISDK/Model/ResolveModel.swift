import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Model resolution logic for language and embedding models.

 Port of `@ai-sdk/ai/src/model/resolve-model.ts`.

 Provides functions to resolve model references (string IDs or direct model instances)
 into standardized V3 model interfaces. Handles V2-to-V3 model adaptation transparently.
 */

// MARK: - V2 to V3 Adapters

/**
 Adapter that wraps a `LanguageModelV2` to conform to `LanguageModelV3`.

 Swift adaptation: Uses delegation pattern instead of JavaScript Proxy.
 All properties and methods are forwarded to the underlying V2 model,
 except `specificationVersion` which returns "v3".
 */
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
private final class LanguageModelV2ToV3Adapter: LanguageModelV3, @unchecked Sendable {
    /// Always returns "v3" to indicate V3 specification
    public let specificationVersion = "v3"

    private let wrappedModel: any LanguageModelV2

    /// Provider identifier (forwarded from V2 model)
    public var provider: String {
        wrappedModel.provider
    }

    /// Model identifier (forwarded from V2 model)
    public var modelId: String {
        wrappedModel.modelId
    }

    /// Supported URL patterns (forwarded from V2 model)
    public var supportedUrls: [String: [NSRegularExpression]] {
        get async throws {
            try await wrappedModel.supportedUrls
        }
    }

    init(wrapping model: any LanguageModelV2) {
        self.wrappedModel = model
    }

    public func doGenerate(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3GenerateResult {
        // Upstream behavior (@ai-sdk/ai): V2->V3 adaptation is currently "best effort".
        // In Swift we avoid unsafeBitCast and instead map the shared fields explicitly.
        let v2Options = _convertLanguageModelV3CallOptionsToV2(options)
        let v2Result = try await wrappedModel.doGenerate(options: v2Options)
        return _convertLanguageModelV2GenerateResultToV3(v2Result)
    }

    public func doStream(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3StreamResult {
        let v2Options = _convertLanguageModelV3CallOptionsToV2(options)
        let v2Result = try await wrappedModel.doStream(options: v2Options)
        return _convertLanguageModelV2StreamResultToV3(v2Result)
    }
}

/**
 Adapter that wraps an `EmbeddingModelV2` to conform to `EmbeddingModelV3`.

 Swift adaptation: Uses delegation pattern instead of JavaScript Proxy.
 All properties and methods are forwarded to the underlying V2 model,
 except `specificationVersion` which returns "v3".
 */
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
private final class EmbeddingModelV2ToV3Adapter<VALUE: Sendable>: EmbeddingModelV3, @unchecked Sendable {
    /// Always returns "v3" to indicate V3 specification
    public let specificationVersion = "v3"

    private let wrappedModel: any EmbeddingModelV2<VALUE>

    /// Provider identifier (forwarded from V2 model)
    public var provider: String {
        wrappedModel.provider
    }

    /// Model identifier (forwarded from V2 model)
    public var modelId: String {
        wrappedModel.modelId
    }

    /// Maximum embeddings per call (forwarded from V2 model)
    public var maxEmbeddingsPerCall: Int? {
        get async throws {
            try await wrappedModel.maxEmbeddingsPerCall
        }
    }

    /// Whether parallel calls are supported (forwarded from V2 model)
    public var supportsParallelCalls: Bool {
        get async throws {
            try await wrappedModel.supportsParallelCalls
        }
    }

    init(wrapping model: any EmbeddingModelV2<VALUE>) {
        self.wrappedModel = model
    }

    public func doEmbed(options: EmbeddingModelV3DoEmbedOptions<VALUE>) async throws -> EmbeddingModelV3DoEmbedResult {
        let v2Options = EmbeddingModelV2DoEmbedOptions<VALUE>(
            values: options.values,
            abortSignal: options.abortSignal,
            providerOptions: options.providerOptions,
            headers: options.headers
        )

        let v2Result = try await wrappedModel.doEmbed(options: v2Options)

        return EmbeddingModelV3DoEmbedResult(
            embeddings: v2Result.embeddings,
            usage: v2Result.usage.map { EmbeddingModelV3Usage(tokens: $0.tokens) },
            providerMetadata: v2Result.providerMetadata,
            response: v2Result.response.map { EmbeddingModelV3ResponseInfo(headers: $0.headers, body: $0.body) },
            warnings: []
        )
    }
}

// MARK: - V2 → V3 Mapping Helpers

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
private func _convertLanguageModelV3CallOptionsToV2(_ options: LanguageModelV3CallOptions) -> LanguageModelV2CallOptions {
    LanguageModelV2CallOptions(
        prompt: _convertLanguageModelV3PromptToV2(options.prompt),
        maxOutputTokens: options.maxOutputTokens,
        temperature: options.temperature,
        stopSequences: options.stopSequences,
        topP: options.topP,
        topK: options.topK,
        presencePenalty: options.presencePenalty,
        frequencyPenalty: options.frequencyPenalty,
        responseFormat: options.responseFormat.map(_convertLanguageModelV3ResponseFormatToV2),
        seed: options.seed,
        tools: options.tools.map { $0.map(_convertLanguageModelV3ToolToV2) },
        toolChoice: options.toolChoice.map(_convertLanguageModelV3ToolChoiceToV2),
        includeRawChunks: options.includeRawChunks,
        abortSignal: options.abortSignal,
        headers: options.headers,
        providerOptions: options.providerOptions
    )
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
private func _convertLanguageModelV3ResponseFormatToV2(_ value: LanguageModelV3ResponseFormat) -> LanguageModelV2ResponseFormat {
    switch value {
    case .text:
        return .text
    case let .json(schema, name, description):
        return .json(schema: schema, name: name, description: description)
    }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
private func _convertLanguageModelV3ToolChoiceToV2(_ value: LanguageModelV3ToolChoice) -> LanguageModelV2ToolChoice {
    switch value {
    case .auto:
        return .auto
    case .none:
        return .none
    case .required:
        return .required
    case let .tool(toolName):
        return .tool(toolName: toolName)
    }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
private func _convertLanguageModelV3ToolToV2(_ value: LanguageModelV3Tool) -> LanguageModelV2Tool {
    switch value {
    case .function(let tool):
        return .function(
            LanguageModelV2FunctionTool(
                name: tool.name,
                inputSchema: tool.inputSchema,
                description: tool.description,
                providerOptions: tool.providerOptions
            )
        )
    case .provider(let tool):
        return .providerDefined(
            LanguageModelV2ProviderDefinedTool(
                id: tool.id,
                name: tool.name,
                args: tool.args
            )
        )
    }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
private func _convertLanguageModelV3PromptToV2(_ prompt: LanguageModelV3Prompt) -> LanguageModelV2Prompt {
    prompt.map(_convertLanguageModelV3MessageToV2)
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
private func _convertLanguageModelV3MessageToV2(_ message: LanguageModelV3Message) -> LanguageModelV2Message {
    switch message {
    case let .system(content, providerOptions):
        return .system(content: content, providerOptions: providerOptions)

    case let .user(content, providerOptions):
        return .user(
            content: content.map(_convertLanguageModelV3UserMessagePartToV2),
            providerOptions: providerOptions
        )

    case let .assistant(content, providerOptions):
        return .assistant(
            content: content.map(_convertLanguageModelV3MessagePartToV2),
            providerOptions: providerOptions
        )

    case let .tool(content, providerOptions):
        return .tool(
            content: content.compactMap(_convertLanguageModelV3ToolMessagePartToV2),
            providerOptions: providerOptions
        )
    }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
private func _convertLanguageModelV3UserMessagePartToV2(_ part: LanguageModelV3UserMessagePart) -> LanguageModelV2UserMessagePart {
    switch part {
    case .text(let value):
        return .text(LanguageModelV2TextPart(text: value.text, providerOptions: value.providerOptions))
    case .file(let value):
        return .file(LanguageModelV2FilePart(
            data: _convertLanguageModelV3DataContentToV2(value.data),
            mediaType: value.mediaType,
            filename: value.filename,
            providerOptions: value.providerOptions
        ))
    }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
private func _convertLanguageModelV3MessagePartToV2(_ part: LanguageModelV3MessagePart) -> LanguageModelV2MessagePart {
    switch part {
    case .text(let value):
        return .text(LanguageModelV2TextPart(text: value.text, providerOptions: value.providerOptions))
    case .file(let value):
        return .file(LanguageModelV2FilePart(
            data: _convertLanguageModelV3DataContentToV2(value.data),
            mediaType: value.mediaType,
            filename: value.filename,
            providerOptions: value.providerOptions
        ))
    case .reasoning(let value):
        return .reasoning(LanguageModelV2ReasoningPart(text: value.text, providerOptions: value.providerOptions))
    case .toolCall(let value):
        return .toolCall(LanguageModelV2ToolCallPart(
            toolCallId: value.toolCallId,
            toolName: value.toolName,
            input: value.input,
            providerExecuted: value.providerExecuted,
            providerOptions: value.providerOptions
        ))
    case .toolResult(let value):
        return .toolResult(LanguageModelV2ToolResultPart(
            toolCallId: value.toolCallId,
            toolName: value.toolName,
            output: _convertLanguageModelV3ToolResultOutputToV2(value.output),
            providerOptions: value.providerOptions
        ))
    }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
private func _convertLanguageModelV3ToolMessagePartToV2(_ part: LanguageModelV3ToolMessagePart) -> LanguageModelV2ToolResultPart? {
    switch part {
    case .toolResult(let value):
        return LanguageModelV2ToolResultPart(
            toolCallId: value.toolCallId,
            toolName: value.toolName,
            output: _convertLanguageModelV3ToolResultOutputToV2(value.output),
            providerOptions: value.providerOptions
        )

    case .toolApprovalResponse:
        // V2 prompt format does not support tool approval responses.
        // Upstream TypeScript compatibility mode is "best effort" and can break here.
        // We drop the part to keep the adapter non-throwing.
        return nil
    }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
private func _convertLanguageModelV3ToolResultOutputToV2(_ output: LanguageModelV3ToolResultOutput) -> LanguageModelV2ToolResultOutput {
    switch output {
    case let .text(value, _):
        return .text(value: value)
    case let .json(value, _):
        return .json(value: value)
    case let .executionDenied(reason, _):
        return .errorText(value: reason ?? "Execution denied")
    case let .errorText(value, _):
        return .errorText(value: value)
    case let .errorJson(value, _):
        return .errorJson(value: value)
    case let .content(value, _):
        return .content(value: value.map(_convertLanguageModelV3ToolResultContentPartToV2))
    }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
private func _convertLanguageModelV3ToolResultContentPartToV2(
    _ part: LanguageModelV3ToolResultContentPart
) -> LanguageModelV2ToolResultContentPart {
    switch part {
    case .text(let text):
        return .text(text: text)
    case let .media(data, mediaType):
        return .media(data: data, mediaType: mediaType)
    }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
private func _convertLanguageModelV3DataContentToV2(_ data: LanguageModelV3DataContent) -> LanguageModelV2DataContent {
    switch data {
    case .data(let data):
        return .data(data)
    case .base64(let string):
        return .base64(string)
    case .url(let url):
        return .url(url)
    }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
private func _convertLanguageModelV2GenerateResultToV3(_ result: LanguageModelV2GenerateResult) -> LanguageModelV3GenerateResult {
    LanguageModelV3GenerateResult(
        content: result.content.map(_convertLanguageModelV2ContentToV3),
        finishReason: LanguageModelV3FinishReason(rawValue: result.finishReason.rawValue) ?? .unknown,
        usage: _convertLanguageModelV2UsageToV3(result.usage),
        providerMetadata: result.providerMetadata,
        request: result.request.map { LanguageModelV3RequestInfo(body: $0.body) },
        response: result.response.map {
            LanguageModelV3ResponseInfo(
                id: $0.id,
                timestamp: $0.timestamp,
                modelId: $0.modelId,
                headers: $0.headers,
                body: $0.body
            )
        },
        warnings: result.warnings.map(_convertLanguageModelV2CallWarningToSharedV3Warning)
    )
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
private func _convertLanguageModelV2StreamResultToV3(_ result: LanguageModelV2StreamResult) -> LanguageModelV3StreamResult {
    let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error>(bufferingPolicy: .unbounded) { continuation in
        let task = Task {
            do {
                for try await part in result.stream {
                    continuation.yield(_convertLanguageModelV2StreamPartToV3(part))
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }

        continuation.onTermination = { @Sendable _ in
            task.cancel()
        }
    }

    return LanguageModelV3StreamResult(
        stream: stream,
        request: result.request.map { LanguageModelV3RequestInfo(body: $0.body) },
        response: result.response.map { LanguageModelV3StreamResponseInfo(headers: $0.headers) }
    )
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
private func _convertLanguageModelV2StreamPartToV3(_ part: LanguageModelV2StreamPart) -> LanguageModelV3StreamPart {
    switch part {
    case let .textStart(id, providerMetadata):
        return .textStart(id: id, providerMetadata: providerMetadata)
    case let .textDelta(id, delta, providerMetadata):
        return .textDelta(id: id, delta: delta, providerMetadata: providerMetadata)
    case let .textEnd(id, providerMetadata):
        return .textEnd(id: id, providerMetadata: providerMetadata)

    case let .reasoningStart(id, providerMetadata):
        return .reasoningStart(id: id, providerMetadata: providerMetadata)
    case let .reasoningDelta(id, delta, providerMetadata):
        return .reasoningDelta(id: id, delta: delta, providerMetadata: providerMetadata)
    case let .reasoningEnd(id, providerMetadata):
        return .reasoningEnd(id: id, providerMetadata: providerMetadata)

    case let .toolInputStart(id, toolName, providerMetadata, providerExecuted):
        return .toolInputStart(
            id: id,
            toolName: toolName,
            providerMetadata: providerMetadata,
            providerExecuted: providerExecuted,
            dynamic: nil,
            title: nil
        )
    case let .toolInputDelta(id, delta, providerMetadata):
        return .toolInputDelta(id: id, delta: delta, providerMetadata: providerMetadata)
    case let .toolInputEnd(id, providerMetadata):
        return .toolInputEnd(id: id, providerMetadata: providerMetadata)

    case let .toolCall(value):
        return .toolCall(_convertLanguageModelV2ToolCallToV3(value))
    case let .toolResult(value):
        return .toolResult(_convertLanguageModelV2ToolResultToV3(value))

    case let .file(value):
        return .file(_convertLanguageModelV2FileToV3(value))
    case let .source(value):
        return .source(_convertLanguageModelV2SourceToV3(value))

    case let .streamStart(warnings):
        return .streamStart(warnings: warnings.map(_convertLanguageModelV2CallWarningToSharedV3Warning))

    case let .responseMetadata(id, modelId, timestamp):
        return .responseMetadata(id: id, modelId: modelId, timestamp: timestamp)

    case let .finish(finishReason, usage, providerMetadata):
        return .finish(
            finishReason: LanguageModelV3FinishReason(rawValue: finishReason.rawValue) ?? .unknown,
            usage: _convertLanguageModelV2UsageToV3(usage),
            providerMetadata: providerMetadata
        )

    case let .raw(rawValue):
        return .raw(rawValue: rawValue)
    case let .error(error):
        return .error(error: error)
    }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
private func _convertLanguageModelV2UsageToV3(_ usage: LanguageModelV2Usage) -> LanguageModelV3Usage {
    let cachedInputTokens = usage.cachedInputTokens ?? 0
    let reasoningTokens = usage.reasoningTokens ?? 0

    return LanguageModelV3Usage(
        inputTokens: .init(
            total: usage.inputTokens,
            noCache: usage.inputTokens.map { $0 - cachedInputTokens },
            cacheRead: usage.cachedInputTokens,
            cacheWrite: nil
        ),
        outputTokens: .init(
            total: usage.outputTokens,
            text: usage.outputTokens.map { $0 - reasoningTokens },
            reasoning: usage.reasoningTokens
        ),
        raw: nil
    )
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
private func _convertLanguageModelV2ContentToV3(_ content: LanguageModelV2Content) -> LanguageModelV3Content {
    switch content {
    case .text(let value):
        return .text(LanguageModelV3Text(text: value.text, providerMetadata: value.providerMetadata))
    case .reasoning(let value):
        return .reasoning(LanguageModelV3Reasoning(text: value.text, providerMetadata: value.providerMetadata))
    case .file(let value):
        return .file(_convertLanguageModelV2FileToV3(value))
    case .source(let value):
        return .source(_convertLanguageModelV2SourceToV3(value))
    case .toolCall(let value):
        return .toolCall(_convertLanguageModelV2ToolCallToV3(value))
    case .toolResult(let value):
        return .toolResult(_convertLanguageModelV2ToolResultToV3(value))
    }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
private func _convertLanguageModelV2ToolCallToV3(_ value: LanguageModelV2ToolCall) -> LanguageModelV3ToolCall {
    LanguageModelV3ToolCall(
        toolCallId: value.toolCallId,
        toolName: value.toolName,
        input: value.input,
        providerExecuted: value.providerExecuted,
        dynamic: nil,
        providerMetadata: value.providerMetadata
    )
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
private func _convertLanguageModelV2ToolResultToV3(_ value: LanguageModelV2ToolResult) -> LanguageModelV3ToolResult {
    LanguageModelV3ToolResult(
        toolCallId: value.toolCallId,
        toolName: value.toolName,
        result: value.result,
        isError: value.isError,
        preliminary: nil,
        dynamic: nil,
        providerMetadata: value.providerMetadata
    )
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
private func _convertLanguageModelV2FileToV3(_ value: LanguageModelV2File) -> LanguageModelV3File {
    LanguageModelV3File(mediaType: value.mediaType, data: _convertLanguageModelV2FileDataToV3(value.data))
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
private func _convertLanguageModelV2FileDataToV3(_ value: LanguageModelV2FileData) -> LanguageModelV3FileData {
    switch value {
    case .base64(let string):
        return .base64(string)
    case .binary(let data):
        return .binary(data)
    }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
private func _convertLanguageModelV2SourceToV3(_ value: LanguageModelV2Source) -> LanguageModelV3Source {
    switch value {
    case let .url(id, url, title, providerMetadata):
        return .url(id: id, url: url, title: title, providerMetadata: providerMetadata)
    case let .document(id, mediaType, title, filename, providerMetadata):
        return .document(
            id: id,
            mediaType: mediaType,
            title: title,
            filename: filename,
            providerMetadata: providerMetadata
        )
    }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
private func _convertLanguageModelV2CallWarningToSharedV3Warning(_ warning: LanguageModelV2CallWarning) -> SharedV3Warning {
    switch warning {
    case let .unsupportedSetting(setting, details):
        return .unsupported(feature: setting, details: details)

    case let .unsupportedTool(tool, details):
        let feature: String
        switch tool {
        case .function(let tool):
            feature = "function tool \(tool.name)"
        case .providerDefined(let tool):
            feature = "provider-defined tool \(tool.id)"
        }
        return .unsupported(feature: feature, details: details)

    case let .other(message):
        return .other(message: message)
    }
}

// MARK: - Global Provider

/**
 Global default provider for model resolution.

 When a model is specified as a string ID, this provider is used to resolve
 the ID to an actual model instance.

 Swift adaptation: Uses a nonisolated(unsafe) static property instead of JavaScript's `globalThis`.
 In TypeScript, this is `globalThis.AI_SDK_DEFAULT_PROVIDER`.

 If no custom provider is set, a default gateway provider should be used
 (gateway functionality is not included in this port, so it must be set explicitly).

 Thread safety: This is marked `nonisolated(unsafe)` to match the JavaScript behavior
 where globalThis can be mutated from any context. Users should ensure proper synchronization
 if accessing from multiple threads.
 */
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
nonisolated(unsafe) public var globalDefaultProvider: (any ProviderV3)? = nil

/**
 Test-only switch to disable usage of `globalDefaultProvider` for string model resolution.

 When `true`, `resolveLanguageModel(.string(_))` and `resolveEmbeddingModel(.string(_))`
 behave as if no global provider is set, regardless of the actual global state.
 This helps eliminate flaky cross-suite interference when tests run in parallel.

 Default: `false`. Do not enable in production code.
 */
// Task-local switch to disable usage of `globalDefaultProvider` for string model resolution.
// Default is `false`. Used by tests to avoid cross-suite interference under parallel execution.
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
enum _ResolveModelContext {
    @TaskLocal static var disableGlobalProvider: Bool = false
    @TaskLocal static var overrideProvider: (any ProviderV3)? = nil
}

// Kept for backward-compat toggling in rare cases; prefer task-local helpers below.
nonisolated(unsafe) public var disableGlobalProviderForStringResolution: Bool = false

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
@discardableResult
public func withGlobalProviderDisabled<T>(_ operation: () throws -> T) rethrows -> T {
    try _ResolveModelContext.$disableGlobalProvider.withValue(true) { try operation() }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
@discardableResult
public func withGlobalProviderDisabled<T>(operation: () async throws -> T) async rethrows -> T {
    try await _ResolveModelContext.$disableGlobalProvider.withValue(true) { try await operation() }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
@discardableResult
public func withGlobalProvider<T>(_ provider: any ProviderV3, _ operation: () throws -> T) rethrows -> T {
    try _ResolveModelContext.$overrideProvider.withValue(provider) { try operation() }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
@discardableResult
public func withGlobalProvider<T>(_ provider: any ProviderV3, operation: () async throws -> T) async rethrows -> T {
    try await _ResolveModelContext.$overrideProvider.withValue(provider) { try await operation() }
}

// MARK: - Resolution Functions

/**
 Resolves a language model reference into a `LanguageModelV3` instance.

 Port of `resolveLanguageModel` from `@ai-sdk/ai/src/model/resolve-model.ts`.

 **Behavior**:
 - If the input is already a V3 model, returns it as-is
 - If the input is a V2 model, wraps it in an adapter that presents a V3 interface
 - If the input is a string ID, resolves it using the global default provider
 - If the input is an unsupported model version, throws `UnsupportedModelVersionError`

 - Parameter model: The language model to resolve (string ID, V2, or V3 model)
 - Returns: A `LanguageModelV3` instance ready for use
 - Throws: `UnsupportedModelVersionError` if the model version is not v2 or v3,
           or `NoSuchProviderError` if no global provider is set for string resolution
 */
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func resolveLanguageModel(_ model: LanguageModel) throws -> any LanguageModelV3 {
    switch model {
    case .string(let id):
        // Resolve string ID using task-local override or global provider
        let disabled = disableGlobalProviderForStringResolution || _ResolveModelContext.disableGlobalProvider
        let provider = _ResolveModelContext.overrideProvider ?? (disabled ? nil : globalDefaultProvider)
        guard let provider else {
            // TypeScript uses gateway as fallback, but we require explicit provider setup
            throw NoSuchProviderError(
                modelId: id,
                modelType: .languageModel,
                providerId: "default",
                availableProviders: [],
                message: "No global default provider set. Set `globalDefaultProvider` before resolving string model IDs."
            )
        }
        return try provider.languageModel(modelId: id)

    case .v3(let model):
        // Already V3, return as-is
        return model

    case .v2(let model):
        // Adapt V2 to V3 interface
        return LanguageModelV2ToV3Adapter(wrapping: model)
    }
}

/**
 Resolves an embedding model reference into an `EmbeddingModelV3` instance.

 Port of `resolveEmbeddingModel` from `@ai-sdk/ai/src/model/resolve-model.ts`.

 **Behavior**:
 - If the input is already a V3 model, returns it as-is
 - If the input is a V2 model, wraps it in an adapter that presents a V3 interface
 - If the input is a string ID, resolves it using the global default provider
 - If the input is an unsupported model version, throws `UnsupportedModelVersionError`

 - Parameter model: The embedding model to resolve (string ID, V2, or V3 model)
 - Returns: An `EmbeddingModelV3` instance ready for use
 - Throws: `UnsupportedModelVersionError` if the model version is not v2 or v3,
           or `NoSuchProviderError` if no global provider is set for string resolution
 */
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func resolveEmbeddingModel<VALUE: Sendable>(_ model: EmbeddingModel<VALUE>) throws -> any EmbeddingModelV3<VALUE> {
    switch model {
    case .string(let id):
        // Resolve string ID using task-local override or global provider
        let disabled = disableGlobalProviderForStringResolution || _ResolveModelContext.disableGlobalProvider
        let provider = _ResolveModelContext.overrideProvider ?? (disabled ? nil : globalDefaultProvider)
        guard let provider else {
            // TypeScript uses gateway as fallback, but we require explicit provider setup
            throw NoSuchProviderError(
                modelId: id,
                modelType: .textEmbeddingModel,
                providerId: "default",
                availableProviders: [],
                message: "No global default provider set. Set `globalDefaultProvider` before resolving string model IDs."
            )
        }
        // TODO AI SDK 6: figure out how to cleanly support different generic types
        // For now, we trust that the provider returns the correct VALUE type.
        // Swift adaptation: Provider returns EmbeddingModelV3<String>, but we need EmbeddingModelV3<VALUE>.
        // We use force cast (as!) which will fail at runtime if types don't match.
        // This matches the TypeScript behavior where type mismatches are caught at runtime.
        return try provider.textEmbeddingModel(modelId: id) as! any EmbeddingModelV3<VALUE>

    case .v3(let model):
        // Already V3, return as-is
        return model

    case .v2(let model):
        // Adapt V2 to V3 interface
        return EmbeddingModelV2ToV3Adapter(wrapping: model)
    }
}
