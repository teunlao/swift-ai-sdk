import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Transforms a full TextStreamPart stream into a UI message stream sequence.

 Port of `@ai-sdk/ai/src/ui/transform-text-to-ui-message-stream.ts`, extended
 for full-stream events (reasoning, sources). Text events are forwarded 1:1;
 optional reasoning and source events are included based on flags.
 */
public func transformFullToUIMessageStream(
    stream: AsyncThrowingStream<TextStreamPart, Error>,
    options: UIMessageTransformOptions = UIMessageTransformOptions()
) -> AsyncThrowingStream<AnyUIMessageChunk, Error> {
    AsyncThrowingStream<AnyUIMessageChunk, Error>(bufferingPolicy: .unbounded) { continuation in
        let task = Task {
            do {
                // Emit stream start if requested
                if options.sendStart {
                    if let mapper = options.messageMetadata, let meta = mapper(.start) {
                        continuation.yield(AnyUIMessageChunk.messageMetadata(meta))
                    }
                    continuation.yield(.start(messageId: nil, messageMetadata: nil))
                }

                var stepOpen = false
                var seenFinish = false

                for try await part in stream {
                    switch part {
                    case .start:
                        // already emitted synthetic start above; ignore
                        break

                    case .startStep:
                        stepOpen = true
                        continuation.yield(.startStep)

                    case let .textStart(id, providerMetadata):
                        if !stepOpen { continuation.yield(.startStep); stepOpen = true }
                        continuation.yield(.textStart(id: id, providerMetadata: providerMetadata))

                    case let .textDelta(id, text, providerMetadata):
                        if !stepOpen { continuation.yield(.startStep); stepOpen = true }
                        continuation.yield(.textDelta(id: id, delta: text, providerMetadata: providerMetadata))

                    case let .textEnd(id, providerMetadata):
                        continuation.yield(.textEnd(id: id, providerMetadata: providerMetadata))

                    case let .reasoningStart(id, providerMetadata):
                        if options.sendReasoning {
                            if !stepOpen { continuation.yield(.startStep); stepOpen = true }
                            continuation.yield(.reasoningStart(id: id, providerMetadata: providerMetadata))
                        }

                    case let .reasoningDelta(id, text, providerMetadata):
                        if options.sendReasoning {
                            if !stepOpen { continuation.yield(.startStep); stepOpen = true }
                            continuation.yield(.reasoningDelta(id: id, delta: text, providerMetadata: providerMetadata))
                        }

                    case let .reasoningEnd(id, providerMetadata):
                        if options.sendReasoning {
                            continuation.yield(.reasoningEnd(id: id, providerMetadata: providerMetadata))
                        }

                    case .source(let source):
                        guard options.sendSources else { break }
                        switch source {
                        case let .url(id, url, title, providerMetadata):
                            continuation.yield(.sourceUrl(
                                sourceId: id,
                                url: url,
                                title: title,
                                providerMetadata: providerMetadata
                            ))
                        case let .document(id, mediaType, title, filename, providerMetadata):
                            continuation.yield(.sourceDocument(
                                sourceId: id,
                                mediaType: mediaType,
                                title: title,
                                filename: filename,
                                providerMetadata: providerMetadata
                            ))
                        }

                    case .file:
                        // Generated file mapping is not represented in UI chunk at this layer.
                        // Upstream UI stream surfaces files via dedicated pathways.
                        break

                    case .toolCall, .toolResult, .toolError, .toolOutputDenied,
                         .toolApprovalRequest, .toolInputStart, .toolInputEnd, .toolInputDelta:
                        // Tool-related events are mapped elsewhere (not part of this transform's scope now)
                        break

                    case let .finishStep(_, _, _, _):
                        if stepOpen { continuation.yield(.finishStep); stepOpen = false }

                    case let .finish(finishReason, totalUsage):
                        if options.sendFinish {
                            if let mapper = options.messageMetadata, let meta = mapper(.finish(finishReason: finishReason, totalUsage: totalUsage)) {
                                continuation.yield(AnyUIMessageChunk.messageMetadata(meta))
                            }
                            continuation.yield(.finish(messageMetadata: nil))
                        }
                        seenFinish = true

                    case .error(let error):
                        continuation.yield(.error(errorText: AISDKProvider.getErrorMessage(error)))

                    case .abort:
                        continuation.yield(.abort)

                    case .raw:
                        // Intentionally ignored for UI stream
                        break
                    }
                }

                // Close open step if upstream ended mid-step
                if stepOpen { continuation.yield(.finishStep) }

                // If upstream finished without explicit finish and flag is set, emit finish
                if options.sendFinish && !seenFinish {
                    continuation.yield(.finish(messageMetadata: nil))
                }
                continuation.finish()
            } catch is CancellationError {
                // Consumer cancelled — do not emit further chunks
            } catch {
                continuation.finish(throwing: error)
            }
        }

        continuation.onTermination = { termination in
            if case .cancelled = termination { task.cancel() }
        }
    }
}
