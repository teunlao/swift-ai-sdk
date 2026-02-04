import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Transforms a text stream into a UI message stream sequence.

 Port of `@ai-sdk/ai/src/ui/transform-text-to-ui-message-stream.ts`.

 **Adaptations**:
 - Web `TransformStream` is modelled as `AsyncThrowingStream` in Swift.
 */
public struct UIMessageTransformOptions: Sendable {
    public var sendStart: Bool
    public var sendFinish: Bool
    public var sendReasoning: Bool
    public var sendSources: Bool
    public var messageMetadata: (@Sendable (TextStreamPart) -> JSONValue?)?

    public init(
        sendStart: Bool = true,
        sendFinish: Bool = true,
        sendReasoning: Bool = false,
        sendSources: Bool = false,
        messageMetadata: (@Sendable (TextStreamPart) -> JSONValue?)? = nil
    ) {
        self.sendStart = sendStart
        self.sendFinish = sendFinish
        self.sendReasoning = sendReasoning
        self.sendSources = sendSources
        self.messageMetadata = messageMetadata
    }
}

public func transformTextToUIMessageStream(
    stream: AsyncThrowingStream<String, Error>,
    options: UIMessageTransformOptions = UIMessageTransformOptions()
) -> AsyncThrowingStream<AnyUIMessageChunk, Error> {
    AsyncThrowingStream(bufferingPolicy: .unbounded) { continuation in
        let task = Task {
            do {
                if options.sendStart {
                    if let mapper = options.messageMetadata, let meta = mapper(.start) {
                        continuation.yield(.messageMetadata(meta))
                    }
                    continuation.yield(.start(messageId: nil, messageMetadata: nil))
                }
                continuation.yield(.startStep)
                continuation.yield(.textStart(id: "text-1", providerMetadata: nil))

                for try await part in stream {
                    continuation.yield(.textDelta(id: "text-1", delta: part, providerMetadata: nil))
                }

                continuation.yield(.textEnd(id: "text-1", providerMetadata: nil))
                continuation.yield(.finishStep)
                if options.sendFinish {
                    if let mapper = options.messageMetadata,
                       let meta = mapper(.finish(finishReason: .unknown, rawFinishReason: nil, totalUsage: createNullLanguageModelUsage()))
                    {
                        continuation.yield(.messageMetadata(meta))
                    }
                    continuation.yield(.finish(messageMetadata: nil))
                }
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
