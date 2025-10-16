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
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }

        continuation.onTermination = { _ in
            task.cancel()
        }
    }
}
