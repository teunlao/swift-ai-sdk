import Foundation
import AISDKProvider
import AISDKProviderUtils

// MARK: - Public API (Milestone 1)

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func streamTextV2<OutputValue: Sendable, PartialOutputValue: Sendable>(
    model modelArg: LanguageModel,
    prompt: String,
    experimentalTransform transforms: [StreamTextTransform] = [],
    stopWhen stopConditions: [StopCondition] = [stepCountIs(1)]
) throws -> DefaultStreamTextV2Result<OutputValue, PartialOutputValue> {
    // Resolve LanguageModel to a v3 model; for milestone 1 only v3 path is supported.
    let resolved: any LanguageModelV3 = try resolveLanguageModel(modelArg)

    let options = LanguageModelV3CallOptions(
        prompt: [
            .user(
                content: [.text(LanguageModelV3TextPart(text: prompt))],
                providerOptions: nil
            )
        ]
    )

    // Bridge provider async stream acquisition without blocking the caller.
    let (bridgeStream, continuation) = AsyncThrowingStream.makeStream(of: LanguageModelV3StreamPart.self)

    // Create result first so we can forward request info into the actor
    let result = DefaultStreamTextV2Result<OutputValue, PartialOutputValue>(
        baseModel: modelArg,
        model: resolved,
        providerStream: bridgeStream,
        transforms: transforms,
        stopConditions: stopConditions
    )

    // Start producer task to fetch provider stream and forward its parts.
    let providerTask = Task {
        do {
            let providerResult = try await resolved.doStream(options: options)
            await result._setRequestInfo(providerResult.request)
            for try await part in providerResult.stream {
                continuation.yield(part)
            }
            continuation.finish()
        } catch {
            continuation.finish(throwing: error)
        }
    }
    continuation.onTermination = { _ in providerTask.cancel() }

    // Allow actor to cancel provider task on early finish
    Task { await result._setProviderCancel { providerTask.cancel() } }

    return result
}

// MARK: - Result Type (Milestone 1)

public final class DefaultStreamTextV2Result<OutputValue: Sendable, PartialOutputValue: Sendable>: Sendable {
    public typealias Output = OutputValue
    public typealias PartialOutput = PartialOutputValue

    private let actor: StreamTextV2Actor
    private let transforms: [StreamTextTransform]
    private let stopConditions: [StopCondition]
    private let totalUsagePromise = DelayedPromise<LanguageModelUsage>()
    private let finishReasonPromise = DelayedPromise<FinishReason>()
    private let stepsPromise = DelayedPromise<[StepResult]>()

    init(
        baseModel: LanguageModel,
        model: any LanguageModelV3,
        providerStream: AsyncThrowingStream<LanguageModelV3StreamPart, Error>,
        transforms: [StreamTextTransform],
        stopConditions: [StopCondition]
    ) {
        self.stopConditions = stopConditions.isEmpty ? [stepCountIs(1)] : stopConditions
        self.actor = StreamTextV2Actor(
            source: providerStream,
            totalUsagePromise: totalUsagePromise,
            finishReasonPromise: finishReasonPromise,
            stepsPromise: stepsPromise
        )
        self.transforms = transforms
        _ = self.actor // keep strong reference
    }

    // Internal: forward provider request info into actor state
    func _setRequestInfo(_ info: LanguageModelV3RequestInfo?) async {
        await actor.setInitialRequest(info)
    }

    // Internal: install provider cancel callback so actor can cancel upstream if it finishes earlier
    func _setProviderCancel(_ cancel: @escaping @Sendable () -> Void) async {
        await actor.setOnTerminate(cancel)
    }

    public var textStream: AsyncThrowingStream<String, Error> {
        // Bridge async actor method into a non-async property via forwarding stream
        AsyncThrowingStream { continuation in
            let task = Task {
                let inner = await actor.textStream()
                do {
                    for try await value in inner {
                        continuation.yield(value)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public var fullStream: AsyncThrowingStream<TextStreamPart, Error> {
        // Build base full stream from actor
        let baseStream = AsyncThrowingStream<TextStreamPart, Error> { continuation in
            let task = Task {
                let inner = await actor.fullStream()
                do {
                    for try await value in inner { continuation.yield(value) }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }

        // Convert to AsyncIterableStream for transforms
        let iterable = createAsyncIterableStream(source: baseStream)
        let options = StreamTextTransformOptions(tools: nil, stopStream: { })
        let transformed = transforms.reduce(iterable) { acc, t in t(acc, options) }

        // Convert back to AsyncThrowingStream for public API
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await part in transformed { continuation.yield(part) }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Accessors (Milestone 3)

    private var finalStep: StepResult {
        get async throws {
            let steps = try await stepsPromise.task.value
            guard let last = steps.last else { throw NoOutputGeneratedError() }
            return last
        }
    }

    public var content: [ContentPart] {
        get async throws { try await finalStep.content }
    }

    public var text: String {
        get async throws { try await finalStep.text }
    }

    public var reasoning: [ReasoningOutput] {
        get async throws { try await finalStep.reasoning }
    }

    public var reasoningText: String? {
        get async throws { try await finalStep.reasoningText }
    }

    public var files: [GeneratedFile] {
        get async throws { try await finalStep.files }
    }

    public var sources: [Source] {
        get async throws { try await finalStep.sources }
    }

    public var toolCalls: [TypedToolCall] {
        get async throws { try await finalStep.toolCalls }
    }

    public var staticToolCalls: [StaticToolCall] {
        get async throws { try await finalStep.staticToolCalls }
    }

    public var dynamicToolCalls: [DynamicToolCall] {
        get async throws { try await finalStep.dynamicToolCalls }
    }

    public var toolResults: [TypedToolResult] {
        get async throws { try await finalStep.toolResults }
    }

    public var staticToolResults: [StaticToolResult] {
        get async throws { try await finalStep.staticToolResults }
    }

    public var dynamicToolResults: [DynamicToolResult] {
        get async throws { try await finalStep.dynamicToolResults }
    }

    public var finishReason: FinishReason {
        get async throws { try await finishReasonPromise.task.value }
    }

    public var usage: LanguageModelUsage {
        get async throws { try await finalStep.usage }
    }

    public var totalUsage: LanguageModelUsage {
        get async throws { try await totalUsagePromise.task.value }
    }

    public var warnings: [CallWarning]? {
        get async throws { try await finalStep.warnings }
    }

    public var steps: [StepResult] {
        get async throws { try await stepsPromise.task.value }
    }

    public var request: LanguageModelRequestMetadata {
        get async throws { try await finalStep.request }
    }

    public var response: StepResultResponse {
        get async throws { try await finalStep.response }
    }

    public var providerMetadata: ProviderMetadata? {
        get async throws { try await finalStep.providerMetadata }
    }
}

// MARK: - Helpers (none needed for milestone 1)
