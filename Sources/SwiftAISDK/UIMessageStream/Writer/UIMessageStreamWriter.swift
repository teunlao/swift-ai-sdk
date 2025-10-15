import Foundation

/**
 Protocol describing a UI message stream writer.

 Port of `@ai-sdk/ai/src/ui-message-stream/ui-message-stream-writer.ts`.
 */
public protocol UIMessageStreamWriter: Sendable {
    associatedtype Message: UIMessageConvertible

    /// Appends a chunk to the current UI message stream.
    func write(_ part: InferUIMessageChunk<Message>)

    /// Merges another stream into the current UI message stream.
    func merge(_ stream: AsyncIterableStream<InferUIMessageChunk<Message>>)

    /// Optional error handler forwarded to nested writers.
    var onError: ErrorHandler? { get }
}
