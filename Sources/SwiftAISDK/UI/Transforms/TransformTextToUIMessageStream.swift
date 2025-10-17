import Foundation

/**
 Transforms a text stream into a UI message stream sequence.

 Port of `@ai-sdk/ai/src/ui/transform-text-to-ui-message-stream.ts`.

 **Adaptations**:
 - Web `TransformStream` is modelled as `AsyncThrowingStream` in Swift.
 */
public func transformTextToUIMessageStream(
    stream: AsyncThrowingStream<String, Error>
) -> AsyncThrowingStream<AnyUIMessageChunk, Error> {
    AsyncThrowingStream { continuation in
        let task = Task {
            do {
                continuation.yield(.start(messageId: nil, messageMetadata: nil))
                continuation.yield(.startStep)
                continuation.yield(.textStart(id: "text-1", providerMetadata: nil))

                for try await part in stream {
                    continuation.yield(.textDelta(id: "text-1", delta: part, providerMetadata: nil))
                }

                continuation.yield(.textEnd(id: "text-1", providerMetadata: nil))
                continuation.yield(.finishStep)
                continuation.yield(.finish(messageMetadata: nil))
                continuation.finish()
            } catch is CancellationError {
                // Consumer cancelled: do not attempt to finish again to avoid
                // re-entrancy via onTermination. Simply exit the task.
            } catch {
                // Propagate real errors to the consumer.
                continuation.finish(throwing: error)
            }
        }

        continuation.onTermination = { termination in
            // Cancel producer only if the consumer actively cancelled.
            // If termination is .finished, the task has either already
            // completed or will complete naturally after finish().
            switch termination {
            case .cancelled:
                task.cancel()
            case .finished:
                break
            @unknown default:
                break
            }
        }
    }
}
