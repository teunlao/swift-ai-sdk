import Foundation
import AISDKProvider

/**
 Converts JSON chunks into Server-Sent Event (SSE) formatted strings.

 Port of `@ai-sdk/ai/src/ui-message-stream/json-to-sse-transform-stream.ts`.

 The transform mirrors the behaviour of the web `TransformStream` implementation:
 every input value is JSON-encoded and emitted as `data: <payload>\n\n`, and the
 sequence is terminated with a final `data: [DONE]\n\n` marker.
 */
public struct JsonToSSETransformStream {
    public init() {}

    public func transform(
        stream: AsyncThrowingStream<JSONValue, Error>
    ) -> AsyncThrowingStream<String, Error> {
        let encoder = SSEEncoder(stream: stream)
        return AsyncThrowingStream(unfolding: {
            try await withTaskCancellationHandler {
                try Task.checkCancellation()
                return try await encoder.next()
            } onCancel: {
                Task { await encoder.cancel() }
            }
        })
    }
}

private actor SSEEncoder {
    private let source: AsyncIterableStream<JSONValue>
    private let iterator: AsyncIterableStream<JSONValue>.AsyncIterator
    private let encoder: JSONEncoder
    private var finished = false

    init(stream: AsyncThrowingStream<JSONValue, Error>) {
        let source = createAsyncIterableStream(source: stream)
        self.source = source
        iterator = source.makeAsyncIterator()
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    }

    func next() async throws -> String? {
        guard !finished else { return nil }
        do {
            guard let element = try await iterator.next() else {
                guard !finished else { return nil }
                finished = true
                return "data: [DONE]\n\n"
            }
            return "data: \(String(decoding: try encoder.encode(element), as: UTF8.self))\n\n"
        } catch {
            finished = true
            throw error
        }
    }

    func cancel() async {
        finished = true
        await source.cancel()
    }
}
