import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Telemetry integration that records the legacy `ai.*` span tree with a `Tracer`:
 an operation span, a span per model call step and a span per tool execution.

 Port of `LegacyOpenTelemetry` from `@ai-sdk/otel/src/legacy-open-telemetry.ts`
 for text and object generation. Upstream ships it in `@ai-sdk/otel`; here it
 stands beside the `Tracer`/`Span` abstraction it records with, which is part of
 this module. The OpenTelemetry context is a task-local span: the provider call
 runs with the step span active and a tool runs with its tool span active, so
 operations started inside a tool become its children.

 ```swift
 let result = try await generateText(
     model: model,
     prompt: "…",
     telemetry: TelemetryOptions(integrations: [LegacyOpenTelemetry(tracer: tracer)])
 )
 ```
 */
public final class LegacyOpenTelemetry: Telemetry, @unchecked Sendable {
    /// The span of the current task context; parents spans started without an explicit parent.
    @TaskLocal public static var activeSpan: (any Span)?

    private let tracer: any Tracer
    private let lock = NSLock()
    private var callStates: [String: CallState] = [:]

    /// - Parameter tracer: The tracer to record with. Swift has no process-wide
    ///   OpenTelemetry tracer provider, so the tracer is always explicit.
    public init(tracer: any Tracer) {
        self.tracer = tracer
    }

    private final class CallState: @unchecked Sendable {
        let operationId: String
        let recording: Recording
        let rootSpan: any Span
        var stepSpan: (any Span)?
        var toolSpans: [String: any Span] = [:]
        var embedSpans: [String: any Span] = [:]
        var rerankSpan: (any Span)?
        let baseAttributes: Attributes
        let settings: Settings

        init(operationId: String, recording: Recording, rootSpan: any Span, baseAttributes: Attributes, settings: Settings) {
            self.operationId = operationId
            self.recording = recording
            self.rootSpan = rootSpan
            self.baseAttributes = baseAttributes
            self.settings = settings
        }
    }

    private struct Recording: Sendable {
        let recordInputs: Bool?
        let recordOutputs: Bool?
        let functionId: String?

        init<Event>(_ event: TelemetryEvent<Event>) {
            recordInputs = event.recordInputs
            recordOutputs = event.recordOutputs
            functionId = event.functionId
        }
    }

    private struct Settings: Sendable {
        var maxOutputTokens: Int?
        var temperature: Double?
        var topP: Double?
        var topK: Int?
        var presencePenalty: Double?
        var frequencyPenalty: Double?
        var stopSequences: [String]?
        var seed: Int?
        var maxRetries: Int?

        var attributes: [(String, AttributeValue?)] {
            [
                ("ai.settings.maxOutputTokens", maxOutputTokens.map(AttributeValue.int)),
                ("ai.settings.temperature", temperature.map(AttributeValue.double)),
                ("ai.settings.topP", topP.map(AttributeValue.double)),
                ("ai.settings.topK", topK.map(AttributeValue.int)),
                ("ai.settings.presencePenalty", presencePenalty.map(AttributeValue.double)),
                ("ai.settings.frequencyPenalty", frequencyPenalty.map(AttributeValue.double)),
                ("ai.settings.stopSequences", stopSequences.map(AttributeValue.stringArray)),
                ("ai.settings.seed", seed.map(AttributeValue.int)),
                ("ai.settings.maxRetries", maxRetries.map(AttributeValue.int)),
            ]
        }
    }

    /// An attribute value, or a value recorded only when inputs or outputs are recorded.
    private enum AttributeSpec {
        case value(AttributeValue?)
        case input(() -> AttributeValue?)
        case output(() -> AttributeValue?)
    }

    private func state(_ callId: String) -> CallState? {
        lock.lock()
        defer { lock.unlock() }
        return callStates[callId]
    }

    private func setState(_ callId: String, _ state: CallState?) {
        lock.lock()
        callStates[callId] = state
        lock.unlock()
    }

    // MARK: - Context

    public func executeLanguageModelCall<T: Sendable>(
        _ event: TelemetryEvent<LanguageModelCallStartEvent>,
        execute: @Sendable () async throws -> T
    ) async throws -> T {
        guard let stepSpan = state(event.callId)?.stepSpan else {
            return try await execute()
        }
        return try await Self.$activeSpan.withValue(stepSpan) { try await execute() }
    }

    public func executeTool<T: Sendable>(
        _ event: TelemetryEvent<ToolExecutionStartEvent>,
        execute: @Sendable () async throws -> T
    ) async throws -> T {
        let toolSpan = state(event.callId).flatMap { state in
            lock.withLock { state.toolSpans[event.toolCall.toolCallId] }
        }
        guard let toolSpan else {
            return try await execute()
        }
        return try await Self.$activeSpan.withValue(toolSpan) { try await execute() }
    }

    // MARK: - Operation start

    public func onStart(_ event: TelemetryEvent<TelemetryStartEvent>) async throws {
        switch event.event {
        case .generateText(let start):
            onGenerateStart(start, recording: Recording(event))
        case .generateObject(let start):
            onObjectOperationStart(start, recording: Recording(event))
        case .embed(let start):
            onEmbedOperationStart(
                callId: start.callId, operationId: start.operationId, provider: start.provider,
                modelId: start.modelId, maxRetries: start.maxRetries, headers: start.headers,
                context: start.runtimeContext, recording: Recording(event),
                input: ("ai.value", .input { .string(telemetryJSON(.string(start.value))) })
            )
        case .embedMany(let start):
            onEmbedOperationStart(
                callId: start.callId, operationId: start.operationId, provider: start.provider,
                modelId: start.modelId, maxRetries: start.maxRetries, headers: start.headers,
                context: start.runtimeContext, recording: Recording(event),
                input: ("ai.values", .input { .stringArray(start.value.map { telemetryJSON(.string($0)) }) })
            )
        case .rerank(let start):
            onEmbedOperationStart(
                callId: start.callId, operationId: start.operationId, provider: start.provider,
                modelId: start.modelId, maxRetries: start.maxRetries, headers: start.headers,
                context: start.runtimeContext, recording: Recording(event),
                input: ("ai.documents", .input { .stringArray(start.documents.map(telemetryJSON)) })
            )
        case .generateSpeech(let start):
            onAudioOperationStart(
                callId: start.callId, operationId: start.operationId, provider: start.provider,
                modelId: start.modelId, headers: start.headers, recording: Recording(event),
                text: start.text, audioSize: nil, audioMediaType: nil
            )
        case .transcribe(let start):
            onAudioOperationStart(
                callId: start.callId, operationId: start.operationId, provider: start.provider,
                modelId: start.modelId, headers: start.headers, recording: Recording(event),
                text: nil, audioSize: start.audio.byteLength, audioMediaType: start.audio.mediaType
            )
        }
    }

    public func onStreamTranscriptionStart(_ event: TelemetryEvent<StreamTranscriptionStartEvent>) async throws {
        let start = event.event
        onAudioOperationStart(
            callId: start.callId, operationId: start.operationId, provider: start.provider,
            modelId: start.modelId, headers: start.headers, recording: Recording(event),
            text: nil, audioSize: start.audio.byteLength, audioMediaType: start.audio.mediaType
        )
    }

    /// Root span of an embedding or reranking operation.
    private func onEmbedOperationStart(
        callId: String,
        operationId: String,
        provider: String,
        modelId: String,
        maxRetries: Int,
        headers: [String: String]?,
        context: Context,
        recording: Recording,
        input: (String, AttributeSpec)
    ) {
        let settings = Settings(maxRetries: maxRetries)
        let baseAttributes = baseTelemetryAttributes(
            provider: provider,
            modelId: modelId,
            settings: settings,
            headers: headers,
            context: context
        )
        var specs = operationName(operationId, recording: recording)
        specs += baseAttributes.map { ($0.key, .value($0.value)) }
        specs.append(input)

        let rootSpan = tracer.startSpan(
            name: operationId,
            options: SpanOptions(attributes: select(recording, specs), parent: Self.activeSpan)
        )
        setState(callId, CallState(
            operationId: operationId,
            recording: recording,
            rootSpan: rootSpan,
            baseAttributes: baseAttributes,
            settings: settings
        ))
    }

    private func onAudioOperationStart(
        callId: String,
        operationId: String,
        provider: String,
        modelId: String,
        headers: [String: String]?,
        recording: Recording,
        text: String?,
        audioSize: Int?,
        audioMediaType: String?
    ) {
        var baseAttributes: Attributes = [
            "ai.model.provider": .string(provider),
            "ai.model.id": .string(modelId),
        ]
        for (key, value) in headers ?? [:] {
            baseAttributes["ai.request.headers.\(key)"] = .string(value)
        }
        var specs = operationName(operationId, recording: recording)
        specs += baseAttributes.map { ($0.key, .value($0.value)) }
        if let text { specs.append(("ai.request.text", .input { .string(text) })) }
        if let audioSize { specs.append(("ai.request.audio.size", .input { .int(audioSize) })) }
        if let audioMediaType { specs.append(("ai.request.audio.mediaType", .input { .string(audioMediaType) })) }

        let rootSpan = tracer.startSpan(
            name: operationId,
            options: SpanOptions(attributes: select(recording, specs), parent: Self.activeSpan)
        )
        setState(callId, CallState(
            operationId: operationId,
            recording: recording,
            rootSpan: rootSpan,
            baseAttributes: baseAttributes,
            settings: Settings()
        ))
    }

    // MARK: - Embedding and reranking model calls

    public func onEmbedStart(_ event: TelemetryEvent<EmbeddingModelCallStartEvent>) async throws {
        guard let state = state(event.callId) else { return }
        var specs = operationName(event.operationId, recording: state.recording)
        specs += state.baseAttributes.map { ($0.key, .value($0.value)) }
        specs.append(("ai.values", .input { .stringArray(event.values.map { telemetryJSON(.string($0)) }) }))
        let span = tracer.startSpan(
            name: event.operationId,
            options: SpanOptions(attributes: select(state.recording, specs), parent: state.rootSpan)
        )
        lock.withLock { state.embedSpans[event.embedCallId] = span }
    }

    public func onEmbedEnd(_ event: TelemetryEvent<EmbeddingModelCallEndEvent>) async throws {
        guard let state = state(event.callId),
              let span = lock.withLock({ state.embedSpans.removeValue(forKey: event.embedCallId) }) else { return }
        span.setAttributes(select(state.recording, [
            ("ai.embeddings", .output { .stringArray(event.embeddings.map(embeddingJSON)) }),
            ("ai.usage.tokens", .value(tokenAttribute(event.usage.tokens))),
        ]))
        span.end()
    }

    public func onRerankStart(_ event: TelemetryEvent<RerankingModelCallStartEvent>) async throws {
        guard let state = state(event.callId) else { return }
        var specs = operationName(event.operationId, recording: state.recording)
        specs += state.baseAttributes.map { ($0.key, .value($0.value)) }
        specs.append(("ai.documents", .input { .stringArray(event.documents.map(telemetryJSON)) }))
        let span = tracer.startSpan(
            name: event.operationId,
            options: SpanOptions(attributes: select(state.recording, specs), parent: state.rootSpan)
        )
        lock.withLock { state.rerankSpan = span }
    }

    public func onRerankEnd(_ event: TelemetryEvent<RerankingModelCallEndEvent>) async throws {
        guard let state = state(event.callId),
              let span = lock.withLock({ () -> (any Span)? in
                  defer { state.rerankSpan = nil }
                  return state.rerankSpan
              }) else { return }
        span.setAttributes(select(state.recording, [
            ("ai.ranking.type", .value(.string(event.documentsType))),
            ("ai.ranking", .output {
                .stringArray(event.ranking.map { ranking in
                    telemetryJSON(.object([
                        "index": .number(Double(ranking.index)),
                        "relevanceScore": .number(ranking.relevanceScore),
                    ]))
                })
            }),
        ]))
        span.end()
    }

    private func onGenerateStart(_ event: GenerateTextStartEvent, recording: Recording) {
        let settings = Settings(
            maxOutputTokens: event.callOptions.maxOutputTokens,
            temperature: event.callOptions.temperature,
            topP: event.callOptions.topP,
            topK: event.callOptions.topK,
            presencePenalty: event.callOptions.presencePenalty,
            frequencyPenalty: event.callOptions.frequencyPenalty,
            stopSequences: event.callOptions.stopSequences,
            seed: event.callOptions.seed,
            maxRetries: event.maxRetries
        )
        let baseAttributes = baseTelemetryAttributes(
            provider: event.provider,
            modelId: event.modelId,
            settings: settings,
            headers: event.headers,
            context: event.runtimeContext
        )

        var specs = operationName(event.operationId, recording: recording)
        specs += baseAttributes.map { ($0.key, .value($0.value)) }
        specs += [
            ("ai.model.provider", .value(.string(event.provider))),
            ("ai.model.id", .value(.string(event.modelId))),
            ("ai.prompt", .input {
                let prompt: JSONValue = .object([
                    "system": event.instructions.map(instructionsJSON) ?? .null,
                    "messages": jsonValue(event.messages),
                ])
                return .string(jsonString(prompt))
            }),
        ]

        let rootSpan = tracer.startSpan(
            name: event.operationId,
            options: SpanOptions(attributes: select(recording, specs), parent: Self.activeSpan)
        )
        setState(event.callId, CallState(
            operationId: event.operationId,
            recording: recording,
            rootSpan: rootSpan,
            baseAttributes: baseAttributes,
            settings: settings
        ))
    }

    private func onObjectOperationStart(_ event: GenerateObjectStartEvent, recording: Recording) {
        let settings = Settings(
            maxOutputTokens: event.maxOutputTokens,
            temperature: event.temperature,
            topP: event.topP,
            topK: event.topK,
            presencePenalty: event.presencePenalty,
            frequencyPenalty: event.frequencyPenalty,
            seed: event.seed,
            maxRetries: event.maxRetries
        )
        let baseAttributes = baseTelemetryAttributes(
            provider: event.provider,
            modelId: event.modelId,
            settings: settings,
            headers: event.headers,
            context: nil
        )

        var specs = operationName(event.operationId, recording: recording)
        specs += baseAttributes.map { ($0.key, .value($0.value)) }
        specs.append(("ai.prompt", .input {
            let prompt: JSONValue
            switch event.prompt {
            case .text(let text): prompt = .string(text)
            case .messages(let messages): prompt = jsonValue(messages)
            case nil: prompt = .null
            }
            let system: JSONValue = event.system.map(instructionsJSON) ?? .null
            let messages: JSONValue = event.messages.map { jsonValue($0) } ?? .null
            let value: JSONValue = .object(["system": system, "prompt": prompt, "messages": messages])
            return .string(jsonString(value))
        }))
        if let schema = event.schema {
            specs.append(("ai.schema", .input { .string(jsonString(schema)) }))
        }
        specs.append(("ai.schema.name", .value(event.schemaName.map(AttributeValue.string))))
        specs.append(("ai.schema.description", .value(event.schemaDescription.map(AttributeValue.string))))
        specs.append(("ai.settings.output", .value(.string(event.output))))

        let rootSpan = tracer.startSpan(
            name: event.operationId,
            options: SpanOptions(attributes: select(recording, specs), parent: Self.activeSpan)
        )
        setState(event.callId, CallState(
            operationId: event.operationId,
            recording: recording,
            rootSpan: rootSpan,
            baseAttributes: baseAttributes,
            settings: settings
        ))
    }

    // MARK: - Steps

    public func onStepStart(_ event: TelemetryEvent<GenerateTextStepStartEvent>) async throws {
        guard let state = state(event.callId) else { return }
        let stepOperationId = state.operationId == "ai.streamText" ? "ai.streamText.doStream" : "ai.generateText.doGenerate"
        let settings = state.settings

        var specs = operationName(stepOperationId, recording: state.recording)
        specs += state.baseAttributes.map { ($0.key, .value($0.value)) }
        specs += [
            ("ai.model.provider", .value(.string(event.provider))),
            ("ai.model.id", .value(.string(event.modelId))),
            ("ai.prompt.messages", .input {
                (try? stringifyForTelemetry(event.promptMessages)).map(AttributeValue.string)
            }),
            ("ai.prompt.tools", .input {
                event.stepTools.map { tools in .stringArray(tools.map { jsonString($0) }) }
            }),
            ("ai.prompt.toolChoice", .input { .string(jsonString(event.stepToolChoice)) }),
            ("gen_ai.system", .value(.string(event.provider))),
            ("gen_ai.request.model", .value(.string(event.modelId))),
            ("gen_ai.request.frequency_penalty", .value(settings.frequencyPenalty.map(AttributeValue.double))),
            ("gen_ai.request.max_tokens", .value(settings.maxOutputTokens.map(AttributeValue.int))),
            ("gen_ai.request.presence_penalty", .value(settings.presencePenalty.map(AttributeValue.double))),
            ("gen_ai.request.stop_sequences", .value(settings.stopSequences.map(AttributeValue.stringArray))),
            ("gen_ai.request.temperature", .value(settings.temperature.map(AttributeValue.double))),
            ("gen_ai.request.top_k", .value(settings.topK.map(AttributeValue.int))),
            ("gen_ai.request.top_p", .value(settings.topP.map(AttributeValue.double))),
        ]

        let stepSpan = tracer.startSpan(
            name: stepOperationId,
            options: SpanOptions(attributes: select(state.recording, specs), parent: state.rootSpan)
        )
        lock.withLock { state.stepSpan = stepSpan }
    }

    public func onStepEnd(_ event: TelemetryEvent<any StepResult>) async throws {
        guard let state = state(event.callId), let stepSpan = lock.withLock({ state.stepSpan }) else { return }
        let step = event.event

        if step.finishReason == .error {
            stepSpan.setStatus(SpanStatus(code: .error))
        }

        let isStreamText = state.operationId == "ai.streamText"
        var specs: [(String, AttributeSpec)] = [
            ("ai.response.finishReason", .value(.string(step.finishReason.rawValue))),
            ("ai.response.text", .output { .string(step.text) }),
            ("ai.response.reasoning", .output { reasoningText(step.reasoning) }),
            ("ai.response.toolCalls", .output { toolCallsJSON(step.toolCalls) }),
            ("ai.response.files", .output { filesJSON(step.files) }),
            ("ai.response.id", .value(.string(step.response.id))),
            ("ai.response.model", .value(.string(step.response.modelId))),
            ("ai.response.timestamp", .value(.string(isoTimestamp(step.response.timestamp)))),
            ("ai.response.providerMetadata", .value(step.providerMetadata.map { .string(jsonString($0)) })),
        ]
        if isStreamText {
            specs += [
                ("ai.response.msToFirstChunk", .value(step.performance.timeToFirstOutputMs.map(AttributeValue.double))),
                ("ai.response.msToFinish", .value(.double(step.performance.responseTimeMs))),
                ("ai.response.avgOutputTokensPerSecond", .value(.double(step.performance.effectiveOutputTokensPerSecond))),
            ]
        }
        specs += usageAttributes(step.usage, details: true)
        specs += [
            ("gen_ai.response.finish_reasons", .value(.stringArray([step.finishReason.rawValue]))),
            ("gen_ai.response.id", .value(.string(step.response.id))),
            ("gen_ai.response.model", .value(.string(step.response.modelId))),
            ("gen_ai.usage.input_tokens", .value(step.usage.inputTokens.map(AttributeValue.int))),
            ("gen_ai.usage.output_tokens", .value(step.usage.outputTokens.map(AttributeValue.int))),
        ]
        stepSpan.setAttributes(select(state.recording, specs))

        if isStreamText, let msToFirstChunk = step.performance.timeToFirstOutputMs {
            stepSpan.addEvent("ai.stream.firstChunk", attributes: ["ai.response.msToFirstChunk": .double(msToFirstChunk)])
        }
        if isStreamText {
            stepSpan.addEvent("ai.stream.finish", attributes: [
                "ai.response.msToFinish": .double(step.performance.responseTimeMs),
                "ai.response.avgOutputTokensPerSecond": .double(step.performance.effectiveOutputTokensPerSecond),
            ])
        }

        stepSpan.end()
        lock.withLock { state.stepSpan = nil }
    }

    public func onObjectStepStart(_ event: TelemetryEvent<GenerateObjectStepStartEvent>) async throws {
        guard let state = state(event.callId) else { return }
        let stepOperationId = state.operationId == "ai.streamObject" ? "ai.streamObject.doStream" : "ai.generateObject.doGenerate"
        let settings = state.settings

        var specs = operationName(stepOperationId, recording: state.recording)
        specs += state.baseAttributes.map { ($0.key, .value($0.value)) }
        specs += [
            ("ai.prompt.messages", .input {
                event.promptMessages.flatMap { try? stringifyForTelemetry($0) }.map(AttributeValue.string)
            }),
            ("gen_ai.system", .value(.string(event.provider))),
            ("gen_ai.request.model", .value(.string(event.modelId))),
            ("gen_ai.request.frequency_penalty", .value(settings.frequencyPenalty.map(AttributeValue.double))),
            ("gen_ai.request.max_tokens", .value(settings.maxOutputTokens.map(AttributeValue.int))),
            ("gen_ai.request.presence_penalty", .value(settings.presencePenalty.map(AttributeValue.double))),
            ("gen_ai.request.temperature", .value(settings.temperature.map(AttributeValue.double))),
            ("gen_ai.request.top_k", .value(settings.topK.map(AttributeValue.int))),
            ("gen_ai.request.top_p", .value(settings.topP.map(AttributeValue.double))),
        ]

        let stepSpan = tracer.startSpan(
            name: stepOperationId,
            options: SpanOptions(attributes: select(state.recording, specs), parent: state.rootSpan)
        )
        lock.withLock { state.stepSpan = stepSpan }
    }

    public func onObjectStepEnd(_ event: TelemetryEvent<GenerateObjectStepEndEvent>) async throws {
        guard let state = state(event.callId), let stepSpan = lock.withLock({ state.stepSpan }) else { return }
        let step = event.event

        if step.finishReason == .error {
            stepSpan.setStatus(SpanStatus(code: .error))
        }

        var specs: [(String, AttributeSpec)] = [
            ("ai.response.finishReason", .value(.string(step.finishReason.rawValue))),
            ("ai.response.object", .output {
                // Normalizes valid JSON; other text is recorded as is.
                if let data = step.objectText.data(using: .utf8),
                   let value = try? JSONDecoder().decode(JSONValue.self, from: data) {
                    return .string(jsonString(value))
                }
                return .string(step.objectText)
            }),
            ("ai.response.id", .value(.string(step.response.id))),
            ("ai.response.model", .value(.string(step.response.modelId))),
            ("ai.response.timestamp", .value(.string(isoTimestamp(step.response.timestamp)))),
            ("ai.response.providerMetadata", .value(step.providerMetadata.map { .string(jsonString($0)) })),
        ]
        specs += usageAttributes(step.usage, details: false)
        specs += [
            ("gen_ai.response.finish_reasons", .value(.stringArray([step.finishReason.rawValue]))),
            ("gen_ai.response.id", .value(.string(step.response.id))),
            ("gen_ai.response.model", .value(.string(step.response.modelId))),
            ("gen_ai.usage.input_tokens", .value(step.usage.inputTokens.map(AttributeValue.int))),
            ("gen_ai.usage.output_tokens", .value(step.usage.outputTokens.map(AttributeValue.int))),
        ]
        stepSpan.setAttributes(select(state.recording, specs))

        if let msToFirstChunk = step.msToFirstChunk {
            stepSpan.addEvent("ai.stream.firstChunk", attributes: ["ai.stream.msToFirstChunk": .double(msToFirstChunk)])
            stepSpan.setAttributes(["ai.stream.msToFirstChunk": .double(msToFirstChunk)])
        }

        stepSpan.end()
        lock.withLock { state.stepSpan = nil }
    }

    // MARK: - Tools

    public func onToolExecutionStart(_ event: TelemetryEvent<ToolExecutionStartEvent>) async throws {
        guard let state = state(event.callId), let stepSpan = lock.withLock({ state.stepSpan }) else { return }
        let toolCall = event.toolCall

        var specs = operationName("ai.toolCall", recording: state.recording)
        specs += state.baseAttributes
            .filter { $0.key.hasPrefix("ai.settings.context.") }
            .map { ($0.key, .value($0.value)) }
        specs += [
            ("ai.toolCall.name", .value(.string(toolCall.toolName))),
            ("ai.toolCall.id", .value(.string(toolCall.toolCallId))),
            ("ai.toolCall.args", .output { .string(jsonString(toolCall.input)) }),
        ]

        let toolSpan = tracer.startSpan(
            name: "ai.toolCall",
            options: SpanOptions(attributes: select(state.recording, specs), parent: stepSpan)
        )
        lock.withLock { state.toolSpans[toolCall.toolCallId] = toolSpan }
    }

    public func onToolExecutionEnd(_ event: TelemetryEvent<ToolExecutionEndEvent>) async throws {
        guard let state = state(event.callId) else { return }
        let toolCallId = event.toolCall.toolCallId
        guard let toolSpan = lock.withLock({ state.toolSpans.removeValue(forKey: toolCallId) }) else { return }

        switch event.toolOutput {
        case .result(let result):
            toolSpan.setAttributes(select(state.recording, [
                ("ai.toolCall.result", .output { .string(jsonString(result.output)) }),
            ]))
        case .error(let error):
            recordSpanError(toolSpan, error.error)
        }
        toolSpan.end()
    }

    // MARK: - Operation end

    public func onEnd(_ event: TelemetryEvent<TelemetryEndEvent>) async throws {
        guard let state = state(event.event.callId) else { return }

        switch event.event {
        case .generateText(let end):
            onGenerateEnd(end, state: state)
        case .generateObject(let end):
            onObjectOperationEnd(end, state: state)
        case .embed(let end):
            state.rootSpan.setAttributes(select(state.recording, [
                ("ai.embedding", .output { .string(embeddingJSON(end.embedding)) }),
                ("ai.usage.tokens", .value(tokenAttribute(end.usage.tokens))),
            ]))
        case .embedMany(let end):
            state.rootSpan.setAttributes(select(state.recording, [
                ("ai.embeddings", .output { .stringArray(end.embedding.map(embeddingJSON)) }),
                ("ai.usage.tokens", .value(tokenAttribute(end.usage.tokens))),
            ]))
        case .rerank:
            break
        case .generateSpeech(let end):
            onAudioOperationEnd(
                state: state, isSpeech: true, text: nil,
                audioSize: end.audio.byteLength, audioMediaType: end.audio.mediaType, audioFormat: end.audio.format,
                usage: end.usage, providerMetadata: end.providerMetadata
            )
        case .transcribe(let end):
            onAudioOperationEnd(
                state: state, isSpeech: false, text: end.text,
                audioSize: end.audio.byteLength, audioMediaType: end.audio.mediaType, audioFormat: nil,
                usage: end.usage, providerMetadata: end.providerMetadata
            )
        }
        state.rootSpan.end()
        setState(event.event.callId, nil)
    }

    public func onStreamTranscriptionEnd(_ event: TelemetryEvent<StreamTranscriptionEndEvent>) async throws {
        let end = event.event
        guard let state = state(end.callId) else { return }
        onAudioOperationEnd(
            state: state, isSpeech: false, text: end.text,
            audioSize: end.audio.byteLength, audioMediaType: end.audio.mediaType, audioFormat: nil,
            usage: end.usage, providerMetadata: end.providerMetadata
        )
        state.rootSpan.end()
        setState(end.callId, nil)
    }

    private func onAudioOperationEnd(
        state: CallState,
        isSpeech: Bool,
        text: String?,
        audioSize: Int,
        audioMediaType: String,
        audioFormat: String?,
        usage: JSONObject?,
        providerMetadata: ProviderMetadata?
    ) {
        var specs: [(String, AttributeSpec)] = []
        if isSpeech {
            specs += [
                ("ai.response.audio.size", .output { .int(audioSize) }),
                ("ai.response.audio.mediaType", .output { .string(audioMediaType) }),
            ]
            if let audioFormat { specs.append(("ai.response.audio.format", .output { .string(audioFormat) })) }
        } else {
            specs += [
                ("ai.request.audio.size", .input { .int(audioSize) }),
                ("ai.request.audio.mediaType", .input { .string(audioMediaType) }),
            ]
            if let text { specs.append(("ai.response.text", .output { .string(text) })) }
        }
        specs += providerUsageAttributes(usage, prefix: "ai.usage").map { ($0.key, .value($0.value)) }
        specs.append(("ai.response.usage", .value(usage.map { .string(jsonString($0)) })))
        specs.append(("ai.response.providerMetadata", .value(providerMetadata.map { .string(jsonString($0)) })))
        state.rootSpan.setAttributes(select(state.recording, specs))
    }

    private func onGenerateEnd(_ event: GenerateTextEndEvent, state: CallState) {
        if event.finishReason == .error {
            state.rootSpan.setStatus(SpanStatus(code: .error))
        }

        var specs: [(String, AttributeSpec)] = [
            ("ai.response.finishReason", .value(.string(event.finishReason.rawValue))),
            ("ai.response.text", .output { .string(event.text) }),
            ("ai.response.reasoning", .output { reasoningText(event.finalStep.reasoning) }),
            ("ai.response.toolCalls", .output { toolCallsJSON(event.toolCalls) }),
            ("ai.response.files", .output { filesJSON(event.files) }),
            ("ai.response.providerMetadata", .value(event.finalStep.providerMetadata.map { .string(jsonString($0)) })),
        ]
        specs += usageAttributes(event.usage, details: true)
        state.rootSpan.setAttributes(select(state.recording, specs))
    }

    private func onObjectOperationEnd(_ event: GenerateObjectEndEvent, state: CallState) {
        if event.finishReason == .error {
            state.rootSpan.setStatus(SpanStatus(code: .error))
        }

        var specs: [(String, AttributeSpec)] = [
            ("ai.response.finishReason", .value(.string(event.finishReason.rawValue))),
            ("ai.response.object", .output { event.object.map { .string(jsonString($0)) } }),
            ("ai.response.providerMetadata", .value(event.providerMetadata.map { .string(jsonString($0)) })),
        ]
        specs += usageAttributes(event.usage, details: false)
        state.rootSpan.setAttributes(select(state.recording, specs))
    }

    public func onAbort(_ event: TelemetryEvent<GenerateTextAbortEvent>) async throws {
        guard let state = state(event.callId) else { return }
        let (toolSpans, stepSpan) = lock.withLock { () -> ([any Span], (any Span)?) in
            let spans = Array(state.toolSpans.values)
            state.toolSpans = [:]
            let step = state.stepSpan
            state.stepSpan = nil
            return (spans, step)
        }
        toolSpans.forEach { $0.end() }
        stepSpan?.end()
        state.rootSpan.end()
        setState(event.callId, nil)
    }

    public func onError(_ event: TelemetryEvent<TelemetryErrorEvent>) async throws {
        guard let state = state(event.callId) else { return }
        let error = event.error

        let (stepSpan, embedSpans, rerankSpan) = lock.withLock { () -> ((any Span)?, [any Span], (any Span)?) in
            defer {
                state.stepSpan = nil
                state.embedSpans = [:]
                state.rerankSpan = nil
            }
            return (state.stepSpan, Array(state.embedSpans.values), state.rerankSpan)
        }
        for span in [stepSpan].compactMap({ $0 }) + embedSpans + [rerankSpan].compactMap({ $0 }) {
            recordSpanError(span, error)
            span.end()
        }
        recordSpanError(state.rootSpan, error)
        state.rootSpan.end()
        setState(event.callId, nil)
    }

    // MARK: - Attributes

    private func select(_ recording: Recording, _ specs: [(String, AttributeSpec)]) -> Attributes {
        var result: Attributes = [:]
        for (key, spec) in specs {
            let value: AttributeValue?
            switch spec {
            case .value(let attribute):
                value = attribute
            case .input(let resolve):
                guard recording.recordInputs != false else { continue }
                value = resolve()
            case .output(let resolve):
                guard recording.recordOutputs != false else { continue }
                value = resolve()
            }
            if let value, let sanitized = sanitizeAttributeValue(value) {
                result[key] = sanitized
            }
        }
        return result
    }

    private func operationName(_ operationId: String, recording: Recording) -> [(String, AttributeSpec)] {
        [
            ("operation.name", .value(.string(recording.functionId.map { "\(operationId) \($0)" } ?? operationId))),
            ("resource.name", .value(recording.functionId.map(AttributeValue.string))),
            ("ai.operationId", .value(.string(operationId))),
            ("ai.telemetry.functionId", .value(recording.functionId.map(AttributeValue.string))),
        ]
    }

    private func baseTelemetryAttributes(
        provider: String,
        modelId: String,
        settings: Settings,
        headers: [String: String]?,
        context: Context?
    ) -> Attributes {
        var attributes: Attributes = [
            "ai.model.provider": .string(provider),
            "ai.model.id": .string(modelId),
        ]
        for (key, value) in settings.attributes {
            if let value { attributes[key] = value }
        }
        for (key, value) in context ?? [:] {
            addRuntimeContextAttribute(&attributes, key: "ai.settings.context.\(key)", value: value)
        }
        for (key, value) in headers ?? [:] {
            attributes["ai.request.headers.\(key)"] = .string(value)
        }
        return attributes
    }

    /// Flattens nested runtime context objects into attribute keys; arrays are kept.
    private func addRuntimeContextAttribute(_ attributes: inout Attributes, key: String, value: JSONValue) {
        switch value {
        case .null:
            return
        case .object(let object):
            for (nestedKey, nestedValue) in object {
                addRuntimeContextAttribute(&attributes, key: "\(key).\(nestedKey)", value: nestedValue)
            }
        case .string(let string):
            attributes[key] = .string(string)
        case .bool(let bool):
            attributes[key] = .bool(bool)
        case .number(let number):
            attributes[key] = .double(number)
        case .array(let array):
            if let strings = array.allValues(as: { if case .string(let s) = $0 { s } else { nil } }) {
                attributes[key] = .stringArray(strings)
            } else if let numbers = array.allValues(as: { if case .number(let n) = $0 { n } else { nil } }) {
                attributes[key] = .doubleArray(numbers)
            } else if let bools = array.allValues(as: { if case .bool(let b) = $0 { b } else { nil } }) {
                attributes[key] = .boolArray(bools)
            }
        }
    }

    private func usageAttributes(_ usage: LanguageModelUsage, details: Bool) -> [(String, AttributeSpec)] {
        var specs: [(String, AttributeSpec)] = [
            ("ai.usage.inputTokens", .value(usage.inputTokens.map(AttributeValue.int))),
            ("ai.usage.outputTokens", .value(usage.outputTokens.map(AttributeValue.int))),
            ("ai.usage.totalTokens", .value(usage.totalTokens.map(AttributeValue.int))),
            ("ai.usage.reasoningTokens", .value(usage.outputTokenDetails.reasoningTokens.map(AttributeValue.int))),
            ("ai.usage.cachedInputTokens", .value(usage.inputTokenDetails.cacheReadTokens.map(AttributeValue.int))),
        ]
        if details {
            specs += [
                ("ai.usage.inputTokenDetails.noCacheTokens", .value(usage.inputTokenDetails.noCacheTokens.map(AttributeValue.int))),
                ("ai.usage.inputTokenDetails.cacheReadTokens", .value(usage.inputTokenDetails.cacheReadTokens.map(AttributeValue.int))),
                ("ai.usage.inputTokenDetails.cacheWriteTokens", .value(usage.inputTokenDetails.cacheWriteTokens.map(AttributeValue.int))),
                ("ai.usage.outputTokenDetails.textTokens", .value(usage.outputTokenDetails.textTokens.map(AttributeValue.int))),
                ("ai.usage.outputTokenDetails.reasoningTokens", .value(usage.outputTokenDetails.reasoningTokens.map(AttributeValue.int))),
            ]
        }
        return specs
    }
}

// MARK: - Helpers

private func recordSpanError(_ span: any Span, _ error: any Error) {
    let message = AISDKProvider.getErrorMessage(error)
    span.recordException(ExceptionEvent(name: String(describing: type(of: error)), message: message))
    span.setStatus(SpanStatus(code: .error, message: message))
}

/// Port of `sanitizeAttributeValue` from `@ai-sdk/otel/src/sanitize-attribute-value.ts`: drops non-finite numbers.
private func sanitizeAttributeValue(_ value: AttributeValue) -> AttributeValue? {
    switch value {
    case .double(let number):
        return number.isFinite ? value : nil
    case .doubleArray(let numbers):
        return numbers.allSatisfy(\.isFinite) ? value : nil
    default:
        return value
    }
}

private let telemetryEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return encoder
}()

/// JSON text of a value, with sorted keys for stable attribute values.
private func jsonString<T: Encodable>(_ value: T) -> String {
    guard let data = try? telemetryEncoder.encode(value) else { return "null" }
    return String(decoding: data, as: UTF8.self)
}

private func jsonValue<T: Encodable>(_ value: T) -> JSONValue {
    guard let data = try? telemetryEncoder.encode(value),
          let json = try? JSONDecoder().decode(JSONValue.self, from: data) else {
        return .null
    }
    return json
}

/// `JSON.stringify` of a JSON value, with JavaScript number formatting.
private func telemetryJSON(_ value: JSONValue) -> String {
    (try? canonicalJSON(value)) ?? "null"
}

private func embeddingJSON(_ embedding: Embedding) -> String {
    telemetryJSON(.array(embedding.map { .number($0) }))
}

/// A token count as an attribute: integral counts as integers; NaN is dropped on selection.
private func tokenAttribute(_ tokens: Double) -> AttributeValue {
    if tokens.isFinite, tokens.rounded() == tokens, abs(tokens) < Double(Int.max) {
        return .int(Int(tokens))
    }
    return .double(tokens)
}

/// Port of `getProviderUsageAttributes` from `@ai-sdk/otel/src/provider-usage-attributes.ts`.
private func providerUsageAttributes(_ usage: JSONObject?, prefix: String) -> Attributes {
    var attributes: Attributes = [:]
    func add(_ value: JSONValue, path: [String]) {
        switch value {
        case .number(let number):
            if number.isFinite, !path.isEmpty {
                attributes["\(prefix).\(path.joined(separator: "."))"] = .double(number)
            }
        case .object(let object):
            for (key, nested) in object {
                let normalized = normalizeUsageKey(key)
                if !normalized.isEmpty { add(nested, path: path + [normalized]) }
            }
        default:
            return
        }
    }
    if let usage { add(.object(usage), path: []) }
    return attributes
}

private let usageKeyAliases: [String: String] = [
    "inputtokens": "input_tokens",
    "prompttokens": "input_tokens",
    "prompttokencount": "input_tokens",
    "totalinputtokens": "input_tokens",
    "outputtokens": "output_tokens",
    "completiontokens": "output_tokens",
    "completiontokencount": "output_tokens",
    "candidatestokencount": "output_tokens",
    "totaltokens": "total_tokens",
    "totaltokencount": "total_tokens",
]

private func normalizeUsageKey(_ key: String) -> String {
    let alphanumeric = key.unicodeScalars.filter { $0.isASCII && CharacterSet.alphanumerics.contains($0) }
    if let alias = usageKeyAliases[String(String.UnicodeScalarView(alphanumeric)).lowercased()] {
        return alias
    }
    var result = ""
    var previous: Character?
    for character in key {
        let isAlphanumeric = character.isASCII && (character.isLetter || character.isNumber)
        if isAlphanumeric {
            if character.isUppercase, let previous, previous.isASCII, previous.isLowercase || previous.isNumber {
                result.append("_")
            }
            result.append(character)
        } else if result.last != "_" {
            result.append("_")
        }
        previous = character
    }
    while result.hasPrefix("_") { result.removeFirst() }
    while result.hasSuffix("_") { result.removeLast() }
    return result.lowercased()
}

private func instructionsJSON(_ instructions: Instructions) -> JSONValue {
    switch instructions {
    case .text(let text): return .string(text)
    case .messages(let messages): return jsonValue(messages)
    }
}

private func reasoningText(_ reasoning: [ReasoningOutput]) -> AttributeValue? {
    reasoning.isEmpty ? nil : .string(reasoning.map(\.text).joined(separator: "\n"))
}

private func toolCallsJSON(_ toolCalls: [TypedToolCall]) -> AttributeValue? {
    guard !toolCalls.isEmpty else { return nil }
    return .string(jsonString(JSONValue.array(toolCalls.map { toolCall in
        .object([
            "toolCallId": .string(toolCall.toolCallId),
            "toolName": .string(toolCall.toolName),
            "input": toolCall.input,
        ])
    })))
}

private func filesJSON(_ files: [GeneratedFile]) -> AttributeValue? {
    guard !files.isEmpty else { return nil }
    return .string(jsonString(JSONValue.array(files.map { file in
        .object([
            "type": .string("file"),
            "mediaType": .string(file.mediaType),
            "data": .string(file.base64),
        ])
    })))
}

/// ISO 8601 with milliseconds, as JavaScript's `Date.toISOString()`.
private func isoTimestamp(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}

private extension Array where Element == JSONValue {
    /// The elements as `T` when every element converts.
    func allValues<T>(as convert: (JSONValue) -> T?) -> [T]? {
        var values: [T] = []
        for element in self {
            guard let value = convert(element) else { return nil }
            values.append(value)
        }
        return values
    }
}
