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

    init(source: AsyncThrowingStream<LanguageModelV3StreamPart, Error>) {
        self.source = source
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
}

enum StreamTextV2Error: Error {
    case providerError(JSONValue)
}
