import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 StreamText V2 - Rewritten to eliminate race conditions.

 Port of `@ai-sdk/ai/src/generate-text/stream-text.ts`.

 Phase 1: Minimal implementation with actor-based state management.
 - textStream only
 - Single-step execution
 - No tools, no transforms, no telemetry
 - Thread-safe state via Actor
 */

// MARK: - Thread-Safe State Management

/// Buffer for fullStream parts (thread-safe)
private actor StreamPartsBuffer {
    private var parts: [TextStreamPart] = []
    private var isFinalized = false

    func append(_ part: TextStreamPart) {
        guard !isFinalized else { return }
        parts.append(part)
    }

    func finalize() {
        isFinalized = true
    }

    func getAllParts() -> [TextStreamPart] {
        parts
    }
}

/// Actor-based state to eliminate race conditions
private actor StreamStateV2 {
    var recordedContent: [ContentPart] = []
    var recordedFinishReason: FinishReason?
    var recordedUsage: LanguageModelUsage?
    var textAccumulator: String = ""
    var isFinished: Bool = false

    // Active content tracking
    var activeTextContent: [String: ActiveTextContent] = [:]
    var activeReasoningContent: [String: ActiveReasoningContent] = [:]

    struct ActiveTextContent {
        var index: Int
        var text: String
        var providerMetadata: ProviderMetadata?
    }

    struct ActiveReasoningContent {
        var index: Int
        var text: String
        var providerMetadata: ProviderMetadata?
    }

    func appendText(_ delta: String) {
        textAccumulator.append(delta)
    }

    func getText() -> String {
        textAccumulator
    }

    func setFinishReason(_ reason: FinishReason) {
        recordedFinishReason = reason
    }

    func setUsage(_ usage: LanguageModelUsage) {
        recordedUsage = usage
    }

    func getFinishReason() -> FinishReason? {
        recordedFinishReason
    }

    func getUsage() -> LanguageModelUsage? {
        recordedUsage
    }

    func markFinished() {
        isFinished = true
    }

    func checkFinished() -> Bool {
        isFinished
    }

    // Content management
    func getContent() -> [ContentPart] {
        recordedContent
    }

    // Text content
    func startText(id: String, metadata: ProviderMetadata?) {
        let index = recordedContent.count
        activeTextContent[id] = ActiveTextContent(index: index, text: "", providerMetadata: metadata)
        recordedContent.append(.text(text: "", providerMetadata: metadata))
    }

    func appendTextDelta(id: String, delta: String, metadata: ProviderMetadata?) {
        guard var active = activeTextContent[id] else { return }

        active.text += delta
        if let metadata {
            active.providerMetadata = metadata
        }
        activeTextContent[id] = active
        recordedContent[active.index] = .text(text: active.text, providerMetadata: active.providerMetadata)
    }

    func endText(id: String, metadata: ProviderMetadata?) {
        guard var active = activeTextContent[id] else { return }

        if let metadata {
            active.providerMetadata = metadata
        }
        activeTextContent.removeValue(forKey: id)
        recordedContent[active.index] = .text(text: active.text, providerMetadata: active.providerMetadata)
    }

    // Reasoning content
    func startReasoning(id: String, metadata: ProviderMetadata?) {
        let index = recordedContent.count
        let reasoning = ReasoningOutput(text: "", providerMetadata: metadata)
        activeReasoningContent[id] = ActiveReasoningContent(index: index, text: "", providerMetadata: metadata)
        recordedContent.append(.reasoning(reasoning))
    }

    func appendReasoningDelta(id: String, delta: String, metadata: ProviderMetadata?) {
        guard var active = activeReasoningContent[id] else { return }

        active.text += delta
        if let metadata {
            active.providerMetadata = metadata
        }
        activeReasoningContent[id] = active
        let reasoning = ReasoningOutput(text: active.text, providerMetadata: active.providerMetadata)
        recordedContent[active.index] = .reasoning(reasoning)
    }

    func endReasoning(id: String, metadata: ProviderMetadata?) {
        guard var active = activeReasoningContent[id] else { return }

        if let metadata {
            active.providerMetadata = metadata
        }
        activeReasoningContent.removeValue(forKey: id)
        let reasoning = ReasoningOutput(text: active.text, providerMetadata: active.providerMetadata)
        recordedContent[active.index] = .reasoning(reasoning)
    }

    // Files and sources
    func addFile(_ file: GeneratedFile) {
        recordedContent.append(.file(file: file, providerMetadata: nil))
    }

    func addSource(_ source: Source) {
        recordedContent.append(.source(type: "source", source: source))
    }
}

// MARK: - Internal Options

public struct StreamTextV2InternalOptions: Sendable {
    public var now: @Sendable () -> Double
    public var generateId: IDGenerator
    public var currentDate: @Sendable () -> Date

    public init(
        now: @escaping @Sendable () -> Double = SwiftAISDK.now,
        generateId: IDGenerator? = nil,
        currentDate: @escaping @Sendable () -> Date = Date.init
    ) {
        self.now = now
        if let generateId {
            self.generateId = generateId
        } else {
            self.generateId = try! createIDGenerator(prefix: "aitxt", size: 24)
        }
        self.currentDate = currentDate
    }
}

// MARK: - Result Type

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public final class DefaultStreamTextResultV2: Sendable {

    private let state = StreamStateV2()
    private let model: any LanguageModelV3
    private let prompt: Prompt
    private let settings: CallSettings
    private let internalOptions: StreamTextV2InternalOptions

    // Promises for async properties
    private let finishReasonPromise = DelayedPromise<FinishReason>()
    private let usagePromise = DelayedPromise<LanguageModelUsage>()
    private let textPromise = DelayedPromise<String>()
    private let contentPromise = DelayedPromise<[ContentPart]>()

    // Stream parts buffer for fullStream
    private let streamPartsBuffer = StreamPartsBuffer()

    init(
        model: any LanguageModelV3,
        prompt: Prompt,
        settings: CallSettings,
        internalOptions: StreamTextV2InternalOptions
    ) {
        self.model = model
        self.prompt = prompt
        self.settings = settings
        self.internalOptions = internalOptions

        // Start pipeline asynchronously
        Task { [weak self] in
            guard let self else { return }
            await self.runPipeline()
        }
    }

    // MARK: - Public Properties

    public var text: String {
        get async throws {
            try await textPromise.task.value
        }
    }

    public var content: [ContentPart] {
        get async throws {
            try await contentPromise.task.value
        }
    }

    public var reasoning: [ReasoningOutput] {
        get async throws {
            let content = try await contentPromise.task.value
            return content.compactMap { part in
                if case .reasoning(let reasoning) = part {
                    return reasoning
                }
                return nil
            }
        }
    }

    public var reasoningText: String? {
        get async throws {
            let reasoningParts = try await reasoning
            guard !reasoningParts.isEmpty else { return nil }
            return reasoningParts.map { $0.text }.joined(separator: "\n")
        }
    }

    public var files: [GeneratedFile] {
        get async throws {
            let content = try await contentPromise.task.value
            return content.compactMap { part in
                if case .file(let file, _) = part {
                    return file
                }
                return nil
            }
        }
    }

    public var sources: [Source] {
        get async throws {
            let content = try await contentPromise.task.value
            return content.compactMap { part in
                if case .source(_, let source) = part {
                    return source
                }
                return nil
            }
        }
    }

    public var finishReason: FinishReason {
        get async throws {
            try await finishReasonPromise.task.value
        }
    }

    public var usage: LanguageModelUsage {
        get async throws {
            try await usagePromise.task.value
        }
    }

    public var fullStream: AsyncThrowingStream<TextStreamPart, Error> {
        AsyncThrowingStream { continuation in
            Task { [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }

                do {
                    try await self.processStream { part in
                        continuation.yield(part)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public var textStream: AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task { [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }

                do {
                    try await self.processStream { part in
                        if case .textDelta(_, let delta, _) = part, !delta.isEmpty {
                            continuation.yield(delta)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Pipeline

    private func runPipeline() async {
        // Pipeline is driven by stream consumption
        // This is here for future expansion
    }

    private func processStream(onPart: @escaping @Sendable (TextStreamPart) -> Void) async throws {
        let standardized = try standardizePrompt(self.prompt)
        let supportedUrls = try await self.model.supportedUrls
        let promptForModel = try await convertToLanguageModelPrompt(
            prompt: standardized,
            supportedUrls: supportedUrls,
            download: nil
        )

        let preparedSettings = try prepareCallSettings(
            maxOutputTokens: self.settings.maxOutputTokens,
            temperature: self.settings.temperature,
            topP: self.settings.topP,
            topK: self.settings.topK,
            presencePenalty: self.settings.presencePenalty,
            frequencyPenalty: self.settings.frequencyPenalty,
            stopSequences: self.settings.stopSequences,
            seed: self.settings.seed
        )

        let callOptions = LanguageModelV3CallOptions(
            prompt: promptForModel,
            maxOutputTokens: preparedSettings.maxOutputTokens,
            temperature: preparedSettings.temperature,
            stopSequences: preparedSettings.stopSequences,
            topP: preparedSettings.topP,
            topK: preparedSettings.topK,
            presencePenalty: preparedSettings.presencePenalty,
            frequencyPenalty: preparedSettings.frequencyPenalty,
            responseFormat: nil,
            seed: preparedSettings.seed,
            tools: nil,
            toolChoice: nil,
            includeRawChunks: false,
            abortSignal: self.settings.abortSignal,
            headers: self.settings.headers,
            providerOptions: nil
        )

        let streamResult = try await self.model.doStream(options: callOptions)

        // Process stream parts
        for try await part in streamResult.stream {
            // Check abort signal
            if let abortSignal = self.settings.abortSignal, abortSignal() {
                await self.state.markFinished()
                await self.streamPartsBuffer.finalize()
                return
            }

            // Convert to TextStreamPart and process
            let textStreamPart = convertToTextStreamPart(part)
            await processStreamPart(textStreamPart)
            await streamPartsBuffer.append(textStreamPart)
            onPart(textStreamPart)
        }

        // Finalize
        await self.state.markFinished()
        await self.streamPartsBuffer.finalize()

        let finalText = await self.state.getText()
        let finalContent = await self.state.getContent()
        let finalReason = await self.state.getFinishReason() ?? .unknown
        let finalUsage = await self.state.getUsage() ?? LanguageModelUsage()

        self.textPromise.resolve(finalText)
        self.contentPromise.resolve(finalContent)
        self.finishReasonPromise.resolve(finalReason)
        self.usagePromise.resolve(finalUsage)
    }

    private func convertToTextStreamPart(_ part: LanguageModelV3StreamPart) -> TextStreamPart {
        switch part {
        case .streamStart:
            return .start
        case .textStart(let id, let metadata):
            return .textStart(id: id, providerMetadata: metadata)
        case .textDelta(let id, let delta, let metadata):
            return .textDelta(id: id, text: delta, providerMetadata: metadata)
        case .textEnd(let id, let metadata):
            return .textEnd(id: id, providerMetadata: metadata)
        case .reasoningStart(let id, let metadata):
            return .reasoningStart(id: id, providerMetadata: metadata)
        case .reasoningDelta(let id, let delta, let metadata):
            return .reasoningDelta(id: id, text: delta, providerMetadata: metadata)
        case .reasoningEnd(let id, let metadata):
            return .reasoningEnd(id: id, providerMetadata: metadata)
        case .file(let file):
            // Convert LanguageModelV3File to GeneratedFile
            let generatedFile: any GeneratedFile
            switch file.data {
            case .base64(let base64String):
                generatedFile = DefaultGeneratedFile(base64: base64String, mediaType: file.mediaType)
            case .binary(let data):
                generatedFile = DefaultGeneratedFile(data: data, mediaType: file.mediaType)
            }
            return .file(generatedFile)
        case .source(let source):
            return .source(source)
        case .finish(let reason, let usage, _):
            return .finish(finishReason: reason, totalUsage: usage)
        default:
            return .start // Placeholder for unsupported parts
        }
    }

    private func processStreamPart(_ part: TextStreamPart) async {
        switch part {
        case .textStart(let id, let metadata):
            await state.startText(id: id, metadata: metadata)

        case .textDelta(let id, let delta, let metadata):
            await state.appendText(delta)
            await state.appendTextDelta(id: id, delta: delta, metadata: metadata)

        case .textEnd(let id, let metadata):
            await state.endText(id: id, metadata: metadata)

        case .reasoningStart(let id, let metadata):
            await state.startReasoning(id: id, metadata: metadata)

        case .reasoningDelta(let id, let delta, let metadata):
            await state.appendReasoningDelta(id: id, delta: delta, metadata: metadata)

        case .reasoningEnd(let id, let metadata):
            await state.endReasoning(id: id, metadata: metadata)

        case .file(let file):
            await state.addFile(file)

        case .source(let source):
            await state.addSource(source)

        case .finish(let reason, let usage):
            await state.setFinishReason(reason)
            await state.setUsage(usage)

        default:
            break
        }
    }
}

// MARK: - Public API

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func streamTextV2(
    model modelArg: LanguageModel,
    system: String? = nil,
    prompt: String? = nil,
    messages: [ModelMessage]? = nil,
    _internal: StreamTextV2InternalOptions = StreamTextV2InternalOptions(),
    settings: CallSettings = CallSettings()
) throws -> DefaultStreamTextResultV2 {
    let resolvedModel = try resolveLanguageModel(modelArg)

    // Validate prompt
    guard (prompt == nil) || (messages == nil) else {
        throw InvalidPromptError(
            prompt: "Prompt(system: \(system ?? "nil"), prompt: \(prompt ?? "nil"), messages: provided)",
            message: "Provide either `prompt` or `messages`, not both."
        )
    }

    let promptInput: Prompt
    if let promptText = prompt {
        promptInput = Prompt.text(promptText, system: system)
    } else if let messageList = messages {
        promptInput = Prompt.messages(messageList, system: system)
    } else {
        throw InvalidPromptError(
            prompt: "Prompt(system: \(system ?? "nil"))",
            message: "Either `prompt` or `messages` must be provided."
        )
    }

    return DefaultStreamTextResultV2(
        model: resolvedModel,
        prompt: promptInput,
        settings: settings,
        internalOptions: _internal
    )
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension DefaultStreamTextResultV2: @unchecked Sendable {}
