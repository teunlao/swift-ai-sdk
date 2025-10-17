import Foundation
import AISDKProvider
import AISDKProviderUtils

/// Internal actor that owns StreamTextV2 pipeline state and emission.
/// Minimal milestone 1 implementation: consume provider parts and emit raw text deltas.
actor StreamTextV2Actor {
    private let source: AsyncThrowingStream<LanguageModelV3StreamPart, Error>
    private let textBroadcaster = AsyncStreamBroadcaster<String>()
    private let fullBroadcaster = AsyncStreamBroadcaster<TextStreamPart>()
    private var started = false
    private var framingEmitted = false

    // Captured metadata/state for framing
    private var capturedWarnings: [LanguageModelV3CallWarning] = []
    private var capturedResponseId: String?
    private var capturedModelId: String?
    private var capturedTimestamp: Date?
    private var openTextIds = Set<String>()

    // Aggregation for step/content
    private var aggregatedText: String = ""
    private var recordedRequest: LanguageModelRequestMetadata = LanguageModelRequestMetadata()

    // Completion sinks (promises owned by result)
    private let totalUsagePromise: DelayedPromise<LanguageModelUsage>
    private let finishReasonPromise: DelayedPromise<FinishReason>
    private let stepsPromise: DelayedPromise<[StepResult]>

    init(
        source: AsyncThrowingStream<LanguageModelV3StreamPart, Error>,
        totalUsagePromise: DelayedPromise<LanguageModelUsage>,
        finishReasonPromise: DelayedPromise<FinishReason>,
        stepsPromise: DelayedPromise<[StepResult]>
    ) {
        self.source = source
        self.totalUsagePromise = totalUsagePromise
        self.finishReasonPromise = finishReasonPromise
        self.stepsPromise = stepsPromise
    }

    func textStream() async -> AsyncThrowingStream<String, Error> {
        Task { [weak self] in
            await self?.ensureStarted()
        }
        return await textBroadcaster.register()
    }

    func fullStream() async -> AsyncThrowingStream<TextStreamPart, Error> {
        Task { [weak self] in
            await self?.ensureStarted()
        }
        return await fullBroadcaster.register()
    }

    private func ensureStarted() async {
        guard !started else { return }
        started = true

        Task { [textBroadcaster, fullBroadcaster, source] in
            do {
                for try await part in source {
                    switch part {
                    case .streamStart(let warnings):
                        capturedWarnings = warnings
                        if !framingEmitted {
                            framingEmitted = true
                            await fullBroadcaster.send(.start)
                            let requestMeta = LanguageModelRequestMetadata(body: nil)
                            await fullBroadcaster.send(.startStep(request: requestMeta, warnings: warnings))
                        }

                    case let .responseMetadata(id, modelId, timestamp):
                        capturedResponseId = id ?? capturedResponseId
                        capturedModelId = modelId ?? capturedModelId
                        capturedTimestamp = timestamp ?? capturedTimestamp

                    case let .textStart(id, providerMetadata):
                        openTextIds.insert(id)
                        await fullBroadcaster.send(.textStart(id: id, providerMetadata: providerMetadata))

                    case let .textDelta(id, delta, providerMetadata):
                        await textBroadcaster.send(delta)
                        if !openTextIds.contains(id) {
                            openTextIds.insert(id)
                            await fullBroadcaster.send(.textStart(id: id, providerMetadata: providerMetadata))
                        }
                        await fullBroadcaster.send(.textDelta(id: id, text: delta, providerMetadata: providerMetadata))
                        aggregatedText.append(delta)

                    case let .textEnd(id, providerMetadata):
                        openTextIds.remove(id)
                        await fullBroadcaster.send(.textEnd(id: id, providerMetadata: providerMetadata))

                    case let .finish(finishReason, usage, providerMetadata):
                        // Close any remaining open text ids
                        for id in openTextIds {
                            await fullBroadcaster.send(.textEnd(id: id, providerMetadata: nil))
                        }
                        openTextIds.removeAll()

                        let response = LanguageModelResponseMetadata(
                            id: capturedResponseId ?? "unknown",
                            timestamp: capturedTimestamp ?? Date(timeIntervalSince1970: 0),
                            modelId: capturedModelId ?? "unknown",
                            headers: nil
                        )

                        await fullBroadcaster.send(
                            .finishStep(
                                response: response,
                                usage: usage,
                                finishReason: finishReason,
                                providerMetadata: providerMetadata
                            )
                        )
                        await fullBroadcaster.send(.finish(finishReason: finishReason, totalUsage: usage))

                        await textBroadcaster.finish()
                        await fullBroadcaster.finish()

                        // Resolve promises with final step snapshot
                        let contentParts: [ContentPart] = aggregatedText.isEmpty
                            ? []
                            : [.text(text: aggregatedText, providerMetadata: nil)]

                        // Build response messages from content using shared util
                        let modelMessages = toResponseMessages(content: contentParts, tools: nil)
                        let responseMessages = convertModelMessagesToResponseMessagesV2(modelMessages)

                        let stepResult = DefaultStepResult(
                            content: contentParts,
                            finishReason: finishReason,
                            usage: usage,
                            warnings: capturedWarnings,
                            request: recordedRequest,
                            response: StepResultResponse(
                                from: response,
                                messages: responseMessages,
                                body: nil
                            ),
                            providerMetadata: providerMetadata
                        )

                        finishReasonPromise.resolve(finishReason)
                        totalUsagePromise.resolve(usage)
                        stepsPromise.resolve([stepResult])

                    case .error(let err):
                        await textBroadcaster.finish(error: StreamTextV2Error.providerError(err))
                        await fullBroadcaster.finish(error: StreamTextV2Error.providerError(err))

                    default:
                        break
                    }
                }
                // If provider ended without explicit .finish, still close the broadcasters
                await textBroadcaster.finish()
                await fullBroadcaster.finish()
            } catch is CancellationError {
                // Consumer cancellation will cancel our task via onTermination of subscribers; just close.
                await textBroadcaster.finish()
                await fullBroadcaster.finish()
            } catch {
                await textBroadcaster.finish(error: error)
                await fullBroadcaster.finish(error: error)
            }
        }
    }

    // Set initial request info from provider (optional)
    func setInitialRequest(_ info: LanguageModelV3RequestInfo?) {
        guard let body = info?.body else { return }
        if let value = try? jsonValue(from: body) {
            recordedRequest = LanguageModelRequestMetadata(body: value)
        }
    }

    // Local conversion of model messages to response messages (assistant/tool only)
    private func convertModelMessagesToResponseMessagesV2(
        _ messages: [ModelMessage]
    ) -> [ResponseMessage] {
        messages.compactMap { message in
            switch message {
            case .assistant(let assistant):
                return .assistant(assistant)
            case .tool(let tool):
                return .tool(tool)
            case .system, .user:
                return nil
            }
        }
    }
}

enum StreamTextV2Error: Error {
    case providerError(JSONValue)
}
