import Foundation

/**
 Pipes a text stream into a streaming response writer.

 Port of `@ai-sdk/ai/src/text-stream/pipe-text-stream-to-response.ts`.

 **Adaptations**:
 - TypeScript writes to Node's `ServerResponse` using a `ReadableStream<Uint8Array>`. The Swift
   port targets the `StreamTextResponseWriter` abstraction and encodes chunks to UTF-8 `Data`
   before writing.
 - Headers are normalised to lowercase to mirror Node's `ServerResponse` behaviour.
 */
public func pipeTextStreamToResponse(
    response: any StreamTextResponseWriter,
    status: Int? = nil,
    statusText: String? = nil,
    headers: [String: String]? = nil,
    textStream: AsyncThrowingStream<String, Error>
) {
    let preparedHeaders = prepareHeaders(
        headers,
        defaultHeaders: ["content-type": "text/plain; charset=utf-8"]
    )

    let normalisedHeaders = Dictionary(uniqueKeysWithValues: preparedHeaders.map { key, value in
        (key.lowercased(), value)
    })

    response.writeHead(
        status: status ?? 200,
        statusText: statusText,
        headers: normalisedHeaders
    )

    Task {
        defer {
            response.end()
        }

        for try await chunk in textStream {
            response.write(Data(chunk.utf8))
        }
    }
}
