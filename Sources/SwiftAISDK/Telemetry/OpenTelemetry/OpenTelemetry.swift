import Foundation
import AISDKProvider
import AISDKProviderUtils

public enum OpenTelemetrySpanType: String, Sendable {
    case operation, step, languageModel, tool, embedding, reranking
}

public struct SpanEnrichment: Sendable {
    public let spanType: OpenTelemetrySpanType
    public let operationId: String
    public let callId: String
    public let runtimeContext: Context?
}

/// Records GenAI semantic-convention spans through the supplied tracer.
public final class OpenTelemetry: Telemetry, @unchecked Sendable {
    @TaskLocal public static var activeSpan: (any Span)?

    private let tracer: any Tracer
    private let enrichSpan: (@Sendable (SpanEnrichment) throws -> Attributes?)?
    private let supplemental: Supplemental
    private let lock = NSLock()
    private var calls: [String: CallState] = [:]

    public init(
        tracer: any Tracer,
        enrichSpan: (@Sendable (SpanEnrichment) throws -> Attributes?)? = nil,
        usage: Bool = false,
        providerMetadata: Bool = false,
        embedding: Bool = false,
        reranking: Bool = false,
        runtimeContext: Bool = false,
        headers: Bool = false,
        toolChoice: Bool = false,
        schema: Bool = false
    ) {
        self.tracer = tracer
        self.enrichSpan = enrichSpan
        self.supplemental = Supplemental(usage: usage, providerMetadata: providerMetadata, embedding: embedding,
            reranking: reranking, runtimeContext: runtimeContext, headers: headers, toolChoice: toolChoice, schema: schema)
    }

    private struct Supplemental: Sendable {
        let usage, providerMetadata, embedding, reranking, runtimeContext, headers, toolChoice, schema: Bool
    }

    private struct Recording: Sendable {
        let inputs: Bool
        let outputs: Bool
        let functionId: String?
        init<T>(_ event: TelemetryEvent<T>) {
            inputs = event.recordInputs != false
            outputs = event.recordOutputs != false
            functionId = event.functionId
        }
    }

    private final class CallState: @unchecked Sendable {
        let operationId: String
        let callId: String
        let recording: Recording
        let root: any Span
        let provider: String
        let modelId: String
        let settings: Attributes
        let base: Attributes
        var runtimeContext: Context?
        var instructions: Instructions?
        var step: (any Span)?
        var inference: (any Span)?
        var definitions: [JSONValue] = []
        var tools: [String: any Span] = [:]
        var embeddings: [String: any Span] = [:]
        var rerank: (any Span)?

        init(operationId: String, callId: String, recording: Recording, root: any Span, provider: String,
             modelId: String, settings: Attributes, base: Attributes, runtimeContext: Context?) {
            self.operationId = operationId
            self.callId = callId
            self.recording = recording
            self.root = root
            self.provider = provider
            self.modelId = modelId
            self.settings = settings
            self.base = base
            self.runtimeContext = runtimeContext
        }
    }

    private func state(_ id: String) -> CallState? { lock.withLock { calls[id] } }

    private func span(_ name: String, type: OpenTelemetrySpanType, state: CallState, attributes: Attributes,
                      parent: (any Span)?, kind: SpanKind = .internal) -> any Span {
        startSpan(name, type: type, operationId: state.operationId, callId: state.callId,
                  context: state.runtimeContext, attributes: attributes, parent: parent, kind: kind)
    }

    private func startSpan(_ name: String, type: OpenTelemetrySpanType, operationId: String, callId: String,
                           context: Context?, attributes: Attributes, parent: (any Span)?, kind: SpanKind) -> any Span {
        let enrichment = SpanEnrichment(spanType: type, operationId: operationId, callId: callId, runtimeContext: context)
        var merged = (try? enrichSpan?(enrichment)) ?? [:]
        merged.merge(attributes) { _, owned in owned }
        return tracer.startSpan(name: name, options: SpanOptions(attributes: sanitize(merged), parent: parent, kind: kind))
    }

    private func start(operationId: String, callId: String, provider: String, modelId: String, recording: Recording,
                       settings: Attributes = [:], context: Context? = nil, headers: [String: String]? = nil,
                       attributes: Attributes = [:], agent: Bool = false, kind: SpanKind = .client) -> CallState {
        let operation = GenAI.operation(operationId)
        let base = baseAttributes(context: context, headers: headers)
        var attrs = base.merging(settings) { _, value in value }
        attrs.merge(attributes) { _, value in value }
        attrs.merge([
            "gen_ai.operation.name": .string(operation), "gen_ai.provider.name": .string(GenAI.provider(provider)),
            "gen_ai.request.model": .string(modelId),
        ]) { _, value in value }
        if agent, let name = recording.functionId { attrs["gen_ai.agent.name"] = .string(name) }
        let root = startSpan("\(operation) \(modelId)", type: .operation, operationId: operationId, callId: callId,
                             context: context, attributes: attrs, parent: Self.activeSpan, kind: kind)
        let state = CallState(operationId: operationId, callId: callId, recording: recording, root: root,
                              provider: provider, modelId: modelId, settings: settings, base: base, runtimeContext: context)
        lock.withLock { calls[callId] = state }
        return state
    }

    public func executeLanguageModelCall<T: Sendable>(_ event: TelemetryEvent<LanguageModelCallStartEvent>,
        execute: @Sendable () async throws -> T) async throws -> T {
        let parent = state(event.callId).flatMap { state in lock.withLock { state.inference ?? state.step } }
        guard let parent else { return try await execute() }
        return try await Self.$activeSpan.withValue(parent) { try await execute() }
    }

    public func executeTool<T: Sendable>(_ event: TelemetryEvent<ToolExecutionStartEvent>,
        execute: @Sendable () async throws -> T) async throws -> T {
        let parent = state(event.callId).flatMap { state in lock.withLock { state.tools[event.toolCall.toolCallId] } }
        guard let parent else { return try await execute() }
        return try await Self.$activeSpan.withValue(parent) { try await execute() }
    }

    public func onStart(_ event: TelemetryEvent<TelemetryStartEvent>) async throws {
        let recording = Recording(event)
        switch event.event {
        case .generateText(let event):
            let attrs = inputAttributes(recording, instructions: event.instructions, messages: GenAI.messages(messages: event.messages))
            _ = start(operationId: event.operationId, callId: event.callId, provider: event.provider, modelId: event.modelId,
                recording: recording, settings: settings(event.callOptions), context: event.runtimeContext, headers: event.headers,
                attributes: attrs, agent: true, kind: .internal)
        case .generateObject(let event):
            let settings = settings(maxTokens: event.maxOutputTokens, temperature: event.temperature, topP: event.topP,
                topK: event.topK, presencePenalty: event.presencePenalty, frequencyPenalty: event.frequencyPenalty, seed: event.seed)
            var attrs = inputAttributes(recording, instructions: event.system, messages: GenAI.messages(prompt: event.prompt, messages: event.messages))
            attrs["gen_ai.output.type"] = .string("json")
            if supplemental.schema {
                if recording.inputs, let schema = event.schema { attrs["ai.schema"] = .string(GenAI.json(schema)) }
                attrs["ai.schema.name"] = event.schemaName.map(AttributeValue.string)
                attrs["ai.schema.description"] = event.schemaDescription.map(AttributeValue.string)
                attrs["ai.settings.output"] = .string(event.output)
            }
            let state = start(operationId: event.operationId, callId: event.callId, provider: event.provider, modelId: event.modelId,
                recording: recording, settings: settings, headers: event.headers, attributes: attrs, agent: true, kind: .internal)
            state.instructions = event.system
        case .embed(let event):
            var attrs: Attributes = [:]
            if supplemental.embedding, recording.inputs { attrs["ai.value"] = .string(GenAI.json(event.value)) }
            _ = start(operationId: event.operationId, callId: event.callId, provider: event.provider, modelId: event.modelId,
                recording: recording, context: event.runtimeContext, headers: event.headers, attributes: attrs)
        case .embedMany(let event):
            var attrs: Attributes = [:]
            if supplemental.embedding, recording.inputs { attrs["ai.values"] = .stringArray(event.value.map { GenAI.json($0) }) }
            _ = start(operationId: event.operationId, callId: event.callId, provider: event.provider, modelId: event.modelId,
                recording: recording, context: event.runtimeContext, headers: event.headers, attributes: attrs)
        case .rerank(let event):
            var attrs: Attributes = [:]
            if supplemental.reranking, recording.inputs { attrs["ai.documents"] = .stringArray(event.documents.map { GenAI.json($0) }) }
            _ = start(operationId: event.operationId, callId: event.callId, provider: event.provider, modelId: event.modelId,
                recording: recording, context: event.runtimeContext, headers: event.headers, attributes: attrs)
        case .generateSpeech(let event):
            audioStart(operationId: event.operationId, callId: event.callId, provider: event.provider, modelId: event.modelId,
                recording: recording, headers: event.headers, text: event.text)
        case .transcribe(let event):
            audioStart(operationId: event.operationId, callId: event.callId, provider: event.provider, modelId: event.modelId,
                recording: recording, headers: event.headers, audioSize: event.audio.byteLength, mediaType: event.audio.mediaType)
        }
    }

    public func onStreamTranscriptionStart(_ event: TelemetryEvent<StreamTranscriptionStartEvent>) async throws {
        audioStart(operationId: event.operationId, callId: event.callId, provider: event.provider, modelId: event.modelId,
            recording: Recording(event), headers: event.headers, audioSize: event.audio.byteLength, mediaType: event.audio.mediaType)
    }

    private func audioStart(operationId: String, callId: String, provider: String, modelId: String, recording: Recording,
                            headers: [String: String]?, text: String? = nil, audioSize: Int? = nil, mediaType: String? = nil) {
        var attrs: Attributes = ["gen_ai.output.type": .string(operationId == "ai.generateSpeech" ? "speech" : "text"),
                                 "gen_ai.request.stream": .bool(operationId == "ai.streamTranscribe")]
        if recording.inputs {
            if let text {
                attrs["gen_ai.input.messages"] = .string(GenAI.json([GenAI.message("user", [GenAI.text(text)])]))
                attrs["ai.request.text"] = .string(text)
            }
            attrs["ai.request.audio.size"] = audioSize.map(AttributeValue.int)
            attrs["ai.request.audio.media_type"] = mediaType.map(AttributeValue.string)
        }
        _ = start(operationId: operationId, callId: callId, provider: provider, modelId: modelId,
                  recording: recording, headers: headers, attributes: attrs, agent: true)
    }

    public func onStepStart(_ event: TelemetryEvent<GenerateTextStepStartEvent>) async throws {
        guard let state = state(event.callId) else { return }
        state.runtimeContext = event.runtimeContext
        var attrs = state.base
        attrs["gen_ai.operation.name"] = .string("agent_step")
        if supplemental.toolChoice, state.recording.inputs { attrs["ai.prompt.toolChoice"] = .string(GenAI.json(event.stepToolChoice)) }
        let step = span("step \(event.steps.count + 1)", type: .step, state: state, attributes: attrs, parent: state.root)
        lock.withLock { state.step = step }
    }

    public func onLanguageModelCallStart(_ event: TelemetryEvent<LanguageModelCallStartEvent>) async throws {
        guard let state = state(event.callId), let step = lock.withLock({ state.step }) else { return }
        var attrs = state.settings
        attrs.removeValue(forKey: "gen_ai.request.seed")
        attrs.merge(inputAttributes(state.recording, instructions: event.instructions, messages: GenAI.messages(messages: event.messages), omitEmpty: true)) { _, value in value }
        attrs["gen_ai.operation.name"] = .string("chat")
        attrs["gen_ai.provider.name"] = .string(GenAI.provider(event.provider))
        attrs["gen_ai.request.model"] = .string(event.modelId)
        if state.recording.inputs, let tools = event.tools { attrs["gen_ai.tool.definitions"] = .string(GenAI.json(tools)) }
        let inference = span("chat \(event.modelId)", type: .languageModel, state: state, attributes: attrs, parent: step, kind: .client)
        lock.withLock {
            state.inference = inference
            state.definitions = (event.tools ?? []).map { GenAI.value($0) }
        }
    }

    public func onLanguageModelCallEnd(_ event: TelemetryEvent<LanguageModelCallEndEvent>) async throws {
        guard let state = state(event.callId), let inference = lock.withLock({ state.inference }) else { return }
        var text = ""
        var reasoning: [ReasoningOutput] = []
        var calls: [TypedToolCall] = []
        var results: [TypedToolResult] = []
        var files: [GeneratedFile] = []
        var outputs: [String: ToolOutput] = [:]
        for part in event.content {
            switch part {
            case .text(let content, _, _): text += content
            case .reasoning(let part): reasoning.append(part)
            case .toolCall(let part, _): calls.append(part)
            case .toolResult(let part, _):
                results.append(part)
                if part.preliminary != true { outputs[part.toolCallId] = .result(part) }
            case .toolError(let part, _): outputs[part.toolCallId] = .error(part)
            case .file(let file, _): files.append(file)
            default: break
            }
        }
        var attrs = responseAttributes(finishReason: event.finishReason, usage: event.usage, metadata: event.providerMetadata)
        attrs["gen_ai.provider.name"] = .string(GenAI.provider(event.provider))
        attrs["gen_ai.response.id"] = .string(event.responseId)
        attrs["gen_ai.response.model"] = .string(event.modelId)
        attrs["gen_ai.client.operation.duration"] = .double(event.performance.responseTimeMs / 1000)
        attrs["gen_ai.client.operation.time_to_first_chunk"] = event.performance.timeToFirstOutputMs.map { .double($0 / 1000) }
        attrs["gen_ai.client.operation.time_per_output_chunk"] = event.performance.timeBetweenOutputChunksMs.map { .double($0.avg / 1000) }
        if state.recording.outputs {
            attrs["gen_ai.output.messages"] = .string(GenAI.json(GenAI.output(text: text, reasoning: reasoning,
                toolCalls: calls, toolResults: results, files: files, finishReason: event.finishReason)))
        }
        var definitions = state.definitions
        var names = Set(definitions.compactMap { definition -> String? in
            guard case .object(let object) = definition, case .string(let name) = object["name"] else { return nil }
            return name
        })
        var observed = false
        for call in calls where call.providerExecuted == true && !names.contains(call.toolName) {
            definitions.append(.object(["type": .string("extension"), "name": .string(call.toolName)]))
            names.insert(call.toolName)
            observed = true
        }
        if observed, state.recording.inputs { attrs["gen_ai.tool.definitions"] = .string(GenAI.json(definitions)) }
        inference.setAttributes(sanitize(attrs))
        if event.finishReason == .error { inference.setStatus(SpanStatus(code: .error)) }
        var recorded: Set<String> = []
        for call in calls where call.providerExecuted == true && recorded.insert(call.toolCallId).inserted {
            let tool = span("execute_tool \(call.toolName)", type: .tool, state: state,
                attributes: toolAttributes(call, recording: state.recording), parent: inference)
            if let output = outputs[call.toolCallId] { finishTool(tool, output: output, recording: state.recording) }
            tool.end()
        }
        inference.end()
        lock.withLock { state.inference = nil; state.definitions = [] }
    }

    public func onStepEnd(_ event: TelemetryEvent<any StepResult>) async throws {
        guard let state = state(event.callId), let step = lock.withLock({ state.step }) else { return }
        step.setAttributes(sanitize(supplementalResponse(usage: event.usage, metadata: event.providerMetadata)))
        if event.finishReason == .error { step.setStatus(SpanStatus(code: .error)) }
        step.end()
        lock.withLock { state.step = nil }
    }

    public func onObjectStepStart(_ event: TelemetryEvent<GenerateObjectStepStartEvent>) async throws {
        guard let state = state(event.callId) else { return }
        let count = state.instructions.map { GenAI.instructions($0).count } ?? 0
        var attrs = state.base.merging(state.settings) { _, value in value }
        attrs.removeValue(forKey: "gen_ai.request.seed")
        attrs.merge(inputAttributes(state.recording, instructions: state.instructions,
            messages: event.promptMessages.map { GenAI.inputMessages(Array($0.dropFirst(count))) })) { _, value in value }
        attrs["gen_ai.operation.name"] = .string("chat")
        attrs["gen_ai.provider.name"] = .string(GenAI.provider(event.provider))
        attrs["gen_ai.request.model"] = .string(event.modelId)
        attrs["gen_ai.output.type"] = .string("json")
        let inference = span("chat \(event.modelId)", type: .languageModel, state: state, attributes: attrs, parent: state.root, kind: .client)
        lock.withLock { state.inference = inference }
    }

    public func onObjectStepEnd(_ event: TelemetryEvent<GenerateObjectStepEndEvent>) async throws {
        guard let state = state(event.callId), let inference = lock.withLock({ state.inference }) else { return }
        var attrs = responseAttributes(finishReason: event.finishReason, usage: event.usage, metadata: event.providerMetadata)
        attrs.removeValue(forKey: "gen_ai.usage.cache_creation.input_tokens")
        attrs["gen_ai.response.id"] = .string(event.response.id)
        attrs["gen_ai.response.model"] = .string(event.response.modelId)
        if state.recording.outputs { attrs["gen_ai.output.messages"] = .string(GenAI.json(GenAI.objectOutput(event.objectText, finishReason: event.finishReason))) }
        inference.setAttributes(sanitize(attrs))
        if event.finishReason == .error { inference.setStatus(SpanStatus(code: .error)) }
        inference.end()
        lock.withLock { state.inference = nil }
    }

    public func onToolExecutionStart(_ event: TelemetryEvent<ToolExecutionStartEvent>) async throws {
        guard let state = state(event.callId) else { return }
        let tool = span("execute_tool \(event.toolCall.toolName)", type: .tool, state: state,
            attributes: toolAttributes(event.toolCall, recording: state.recording), parent: state.step ?? state.root)
        lock.withLock { state.tools[event.toolCall.toolCallId] = tool }
    }

    public func onToolExecutionEnd(_ event: TelemetryEvent<ToolExecutionEndEvent>) async throws {
        guard let state = state(event.callId), let tool = lock.withLock({ state.tools.removeValue(forKey: event.toolCall.toolCallId) }) else { return }
        tool.setAttributes(sanitize(["gen_ai.execute_tool.duration": .double(event.toolExecutionMs / 1000)]))
        finishTool(tool, output: event.toolOutput, recording: state.recording)
        tool.end()
    }

    private func toolAttributes(_ call: TypedToolCall, recording: Recording) -> Attributes {
        var attrs: Attributes = ["gen_ai.operation.name": .string("execute_tool"), "gen_ai.tool.name": .string(call.toolName),
            "gen_ai.tool.call.id": .string(call.toolCallId), "gen_ai.tool.type": .string(call.providerExecuted == true ? "extension" : "function")]
        if recording.inputs { attrs["gen_ai.tool.call.arguments"] = .string(GenAI.json(call.input)) }
        return attrs
    }

    private func finishTool(_ span: any Span, output: ToolOutput, recording: Recording) {
        switch output {
        case .result(let result):
            if recording.outputs { span.setAttribute("gen_ai.tool.call.result", value: .string(GenAI.json(result.output))) }
        case .error(let error): recordError(span, error.error)
        }
    }

    public func onEmbedStart(_ event: TelemetryEvent<EmbeddingModelCallStartEvent>) async throws {
        guard let state = state(event.callId) else { return }
        var attrs = state.base.merging(modelAttributes(state, operation: "embeddings")) { _, value in value }
        if supplemental.embedding, state.recording.inputs { attrs["ai.values"] = .stringArray(event.values.map { GenAI.json($0) }) }
        let embed = span("embeddings \(state.modelId)", type: .embedding, state: state, attributes: attrs, parent: state.root, kind: .client)
        lock.withLock { state.embeddings[event.embedCallId] = embed }
    }

    public func onEmbedEnd(_ event: TelemetryEvent<EmbeddingModelCallEndEvent>) async throws {
        guard let state = state(event.callId), let embed = lock.withLock({ state.embeddings.removeValue(forKey: event.embedCallId) }) else { return }
        var attrs: Attributes = ["gen_ai.usage.input_tokens": tokenAttribute(event.usage.tokens)]
        if supplemental.embedding, state.recording.outputs { attrs["ai.embeddings"] = .stringArray(event.embeddings.map(embeddingJSON)) }
        embed.setAttributes(sanitize(attrs))
        embed.end()
    }

    public func onRerankStart(_ event: TelemetryEvent<RerankingModelCallStartEvent>) async throws {
        guard let state = state(event.callId) else { return }
        var attrs = state.base.merging(modelAttributes(state, operation: "rerank")) { _, value in value }
        if supplemental.reranking, state.recording.inputs { attrs["ai.documents"] = .stringArray(event.documents.map { GenAI.json($0) }) }
        let rerank = span("rerank \(state.modelId)", type: .reranking, state: state, attributes: attrs, parent: state.root, kind: .client)
        lock.withLock { state.rerank = rerank }
    }

    public func onRerankEnd(_ event: TelemetryEvent<RerankingModelCallEndEvent>) async throws {
        guard let state = state(event.callId), let rerank = lock.withLock({ () -> (any Span)? in defer { state.rerank = nil }; return state.rerank }) else { return }
        if supplemental.reranking {
            var attrs: Attributes = ["ai.ranking.type": .string(event.documentsType)]
            if state.recording.outputs {
                attrs["ai.ranking"] = .stringArray(event.ranking.map { ranking in
                    GenAI.json(JSONValue.object(["index": .number(Double(ranking.index)), "relevanceScore": .number(ranking.relevanceScore)]))
                })
            }
            rerank.setAttributes(attrs)
        }
        rerank.end()
    }

    public func onEnd(_ event: TelemetryEvent<TelemetryEndEvent>) async throws {
        guard let state = state(event.event.callId) else { return }
        var attrs: Attributes = [:]
        switch event.event {
        case .generateText(let end):
            attrs = responseAttributes(finishReason: end.finishReason, usage: end.usage, metadata: end.finalStep.providerMetadata)
            if state.recording.outputs { attrs["gen_ai.output.messages"] = .string(GenAI.json(GenAI.output(text: end.text,
                reasoning: end.finalStep.reasoning, toolCalls: end.toolCalls, toolResults: end.toolResults, files: end.files, finishReason: end.finishReason))) }
            if end.finishReason == .error { state.root.setStatus(SpanStatus(code: .error)) }
        case .generateObject(let end):
            attrs = responseAttributes(finishReason: end.finishReason, usage: end.usage, metadata: end.providerMetadata)
            attrs.removeValue(forKey: "gen_ai.usage.cache_creation.input_tokens")
            if state.recording.outputs, let object = end.object { attrs["gen_ai.output.messages"] = .string(GenAI.json(GenAI.objectOutput(GenAI.json(object), finishReason: end.finishReason))) }
            if end.finishReason == .error { state.root.setStatus(SpanStatus(code: .error)) }
        case .embed(let end):
            if supplemental.embedding, state.recording.outputs { attrs["ai.embedding"] = .string(embeddingJSON(end.embedding)) }
        case .embedMany(let end):
            if supplemental.embedding, state.recording.outputs { attrs["ai.embeddings"] = .stringArray(end.embedding.map(embeddingJSON)) }
        case .rerank: break
        case .generateSpeech(let end):
            attrs = audioEnd(state, speech: true, text: nil, audioSize: end.audio.byteLength, mediaType: end.audio.mediaType,
                             format: end.audio.format, usage: end.usage, metadata: end.providerMetadata)
        case .transcribe(let end):
            attrs = audioEnd(state, speech: false, text: end.text, audioSize: end.audio.byteLength, mediaType: end.audio.mediaType,
                             usage: end.usage, metadata: end.providerMetadata)
        }
        state.root.setAttributes(sanitize(attrs))
        state.root.end()
        _ = lock.withLock { calls.removeValue(forKey: state.callId) }
    }

    public func onStreamTranscriptionEnd(_ event: TelemetryEvent<StreamTranscriptionEndEvent>) async throws {
        guard let state = state(event.callId) else { return }
        state.root.setAttributes(sanitize(audioEnd(state, speech: false, text: event.text, audioSize: event.audio.byteLength,
            mediaType: event.audio.mediaType, usage: event.usage, metadata: event.providerMetadata)))
        state.root.end()
        _ = lock.withLock { calls.removeValue(forKey: state.callId) }
    }

    private func audioEnd(_ state: CallState, speech: Bool, text: String?, audioSize: Int, mediaType: String,
                          format: String? = nil, usage: JSONObject?, metadata: ProviderMetadata?) -> Attributes {
        var attrs = providerUsageAttributes(usage, prefix: "gen_ai.usage")
        if speech, state.recording.outputs {
            attrs["ai.response.audio.size"] = .int(audioSize)
            attrs["ai.response.audio.media_type"] = .string(mediaType)
            attrs["ai.response.audio.format"] = format.map(AttributeValue.string)
        } else if !speech {
            if state.recording.inputs {
                attrs["ai.request.audio.size"] = .int(audioSize)
                attrs["ai.request.audio.media_type"] = .string(mediaType)
            }
            if state.recording.outputs, let text {
                attrs["ai.response.text"] = .string(text)
                attrs["gen_ai.output.messages"] = .string(GenAI.json([GenAI.message("assistant", [GenAI.text(text)])]))
            }
        }
        if supplemental.usage { attrs["ai.response.usage"] = usage.map { .string(GenAI.json($0)) } }
        if supplemental.providerMetadata { attrs["ai.response.providerMetadata"] = metadata.map { .string(GenAI.json($0)) } }
        return attrs
    }

    public func onAbort(_ event: TelemetryEvent<GenerateTextAbortEvent>) async throws { close(event.callId) }
    public func onError(_ event: TelemetryEvent<TelemetryErrorEvent>) async throws { close(event.callId, error: event.error) }

    private func close(_ callId: String, error: (any Error)? = nil) {
        guard let state = lock.withLock({ calls.removeValue(forKey: callId) }) else { return }
        let spans = lock.withLock {
            Array(state.tools.values) + [state.inference, state.step].compactMap { $0 }
                + Array(state.embeddings.values) + [state.rerank].compactMap { $0 } + [state.root]
        }
        for span in spans {
            if let error { recordError(span, error) }
            span.end()
        }
    }

    private func inputAttributes(_ recording: Recording, instructions: Instructions?, messages: @autoclosure () -> [JSONValue]?, omitEmpty: Bool = false) -> Attributes {
        guard recording.inputs else { return [:] }
        var attrs: Attributes = [:]
        if let instructions { attrs["gen_ai.system_instructions"] = .string(GenAI.json(GenAI.instructions(instructions))) }
        if let messages = messages(), !omitEmpty || !messages.isEmpty { attrs["gen_ai.input.messages"] = .string(GenAI.json(messages)) }
        return attrs
    }

    private func modelAttributes(_ state: CallState, operation: String) -> Attributes {
        ["gen_ai.operation.name": .string(operation), "gen_ai.provider.name": .string(GenAI.provider(state.provider)), "gen_ai.request.model": .string(state.modelId)]
    }

    private func settings(_ options: LanguageModelCallOptions) -> Attributes {
        settings(maxTokens: options.maxOutputTokens, temperature: options.temperature, topP: options.topP, topK: options.topK,
            presencePenalty: options.presencePenalty, frequencyPenalty: options.frequencyPenalty, stop: options.stopSequences, seed: options.seed)
    }

    private func settings(maxTokens: Int?, temperature: Double?, topP: Double?, topK: Int?, presencePenalty: Double?,
                          frequencyPenalty: Double?, stop: [String]? = nil, seed: Int?) -> Attributes {
        var attrs: Attributes = [:]
        attrs["gen_ai.request.max_tokens"] = maxTokens.map(AttributeValue.int)
        attrs["gen_ai.request.temperature"] = temperature.map(AttributeValue.double)
        attrs["gen_ai.request.top_p"] = topP.map(AttributeValue.double)
        attrs["gen_ai.request.top_k"] = topK.map(AttributeValue.int)
        attrs["gen_ai.request.presence_penalty"] = presencePenalty.map(AttributeValue.double)
        attrs["gen_ai.request.frequency_penalty"] = frequencyPenalty.map(AttributeValue.double)
        attrs["gen_ai.request.stop_sequences"] = stop.map(AttributeValue.stringArray)
        attrs["gen_ai.request.seed"] = seed.map(AttributeValue.int)
        return attrs
    }

    private func responseAttributes(finishReason: FinishReason, usage: LanguageModelUsage, metadata: ProviderMetadata?) -> Attributes {
        var attrs = supplementalResponse(usage: usage, metadata: metadata)
        attrs["gen_ai.response.finish_reasons"] = .stringArray([finishReason.rawValue])
        attrs["gen_ai.usage.input_tokens"] = usage.inputTokens.map(AttributeValue.int)
        attrs["gen_ai.usage.output_tokens"] = usage.outputTokens.map(AttributeValue.int)
        attrs["gen_ai.usage.cache_read.input_tokens"] = usage.inputTokenDetails.cacheReadTokens.map(AttributeValue.int)
        attrs["gen_ai.usage.cache_creation.input_tokens"] = usage.inputTokenDetails.cacheWriteTokens.map(AttributeValue.int)
        return attrs
    }

    private func supplementalResponse(usage: LanguageModelUsage, metadata: ProviderMetadata?) -> Attributes {
        var attrs: Attributes = [:]
        if supplemental.usage {
            attrs["ai.usage.inputTokenDetails.noCacheTokens"] = usage.inputTokenDetails.noCacheTokens.map(AttributeValue.int)
            attrs["ai.usage.outputTokenDetails.textTokens"] = usage.outputTokenDetails.textTokens.map(AttributeValue.int)
            attrs["ai.usage.outputTokenDetails.reasoningTokens"] = usage.outputTokenDetails.reasoningTokens.map(AttributeValue.int)
        }
        if supplemental.providerMetadata { attrs["ai.response.providerMetadata"] = metadata.map { .string(GenAI.json($0)) } }
        return attrs
    }

    private func baseAttributes(context: Context?, headers: [String: String]?) -> Attributes {
        var attrs: Attributes = [:]
        if supplemental.headers { for (key, value) in headers ?? [:] { attrs["ai.request.headers.\(key)"] = .string(value) } }
        if supplemental.runtimeContext {
            func flatten(_ value: JSONValue, key: String) {
                switch value {
                case .null: break
                case .object(let object): for (name, value) in object { flatten(value, key: "\(key).\(name)") }
                case .string(let value): attrs[key] = .string(value)
                case .number(let value): attrs[key] = .double(value)
                case .bool(let value): attrs[key] = .bool(value)
                case .array(let values):
                    if values.allSatisfy({ if case .string = $0 { true } else { false } }) {
                        attrs[key] = .stringArray(values.compactMap { if case .string(let value) = $0 { value } else { nil } })
                    } else if values.allSatisfy({ if case .number = $0 { true } else { false } }) {
                        attrs[key] = .doubleArray(values.compactMap { if case .number(let value) = $0 { value } else { nil } })
                    } else if values.allSatisfy({ if case .bool = $0 { true } else { false } }) {
                        attrs[key] = .boolArray(values.compactMap { if case .bool(let value) = $0 { value } else { nil } })
                    }
                }
            }
            for (key, value) in context ?? [:] { flatten(value, key: "ai.settings.context.\(key)") }
        }
        return attrs
    }
}

private func sanitize(_ attributes: Attributes) -> Attributes {
    attributes.filter { _, value in
        switch value {
        case .double(let number): number.isFinite
        case .doubleArray(let numbers): numbers.allSatisfy(\.isFinite)
        default: true
        }
    }
}

private func recordError(_ span: any Span, _ error: any Error) {
    let message = AISDKProvider.getErrorMessage(error)
    span.recordException(ExceptionEvent(name: String(describing: type(of: error)), message: message))
    span.setStatus(SpanStatus(code: .error, message: message))
}

private func embeddingJSON(_ embedding: Embedding) -> String {
    (try? canonicalJSON(.array(embedding.map(JSONValue.number)))) ?? "null"
}

private func tokenAttribute(_ tokens: Double) -> AttributeValue {
    if tokens.isFinite, tokens.rounded() == tokens, abs(tokens) < Double(Int.max) { return .int(Int(tokens)) }
    return .double(tokens)
}

private func providerUsageAttributes(_ usage: JSONObject?, prefix: String) -> Attributes {
    var attributes: Attributes = [:]
    func add(_ value: JSONValue, path: [String]) {
        switch value {
        case .number(let number):
            if number.isFinite, !path.isEmpty { attributes["\(prefix).\(path.joined(separator: "."))"] = tokenAttribute(number) }
        case .object(let object):
            for (key, nested) in object {
                let normalized = normalizeUsageKey(key)
                if !normalized.isEmpty { add(nested, path: path + [normalized]) }
            }
        default: break
        }
    }
    if let usage { add(.object(usage), path: []) }
    return attributes
}

private func normalizeUsageKey(_ key: String) -> String {
    let aliases = ["inputtokens": "input_tokens", "prompttokens": "input_tokens", "prompttokencount": "input_tokens",
        "totalinputtokens": "input_tokens", "outputtokens": "output_tokens", "completiontokens": "output_tokens",
        "completiontokencount": "output_tokens", "candidatestokencount": "output_tokens", "totaltokens": "total_tokens", "totaltokencount": "total_tokens"]
    let alphanumeric = key.unicodeScalars.filter { $0.isASCII && CharacterSet.alphanumerics.contains($0) }
    if let alias = aliases[String(String.UnicodeScalarView(alphanumeric)).lowercased()] { return alias }
    var result = ""
    var previous: Character?
    for character in key {
        if character.isASCII && (character.isLetter || character.isNumber) {
            if character.isUppercase, let previous, previous.isASCII, previous.isLowercase || previous.isNumber { result.append("_") }
            result.append(character)
        } else if result.last != "_" { result.append("_") }
        previous = character
    }
    while result.hasPrefix("_") { result.removeFirst() }
    while result.hasSuffix("_") { result.removeLast() }
    return result.lowercased()
}
