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
        AsyncThrowingStream { continuation in
            Task {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

                do {
                    for try await element in stream {
                        let data = try encoder.encode(element)
                        guard let text = String(data: data, encoding: .utf8) else {
                            continue
                        }
                        continuation.yield("data: \(text)\n\n")
                    }

                    continuation.yield("data: [DONE]\n\n")
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
