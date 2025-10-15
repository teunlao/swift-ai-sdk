import Foundation

/**
 Creates a `TextStreamResponse` with UTF-8 encoded text defaults.

 Port of `@ai-sdk/ai/src/text-stream/create-text-stream-response.ts`.

 **Adaptations**:
 - TypeScript produces a `Response` whose body is a `ReadableStream<Uint8Array>` created via
   `TextEncoderStream`. The Swift port surfaces the placeholder `TextStreamResponse` wrapper that
   carries an `AsyncThrowingStream<String, Error>` together with metadata mirroring `ResponseInit`.
 - Headers are represented as `[String: String]` while preserving case-insensitive semantics.
 */
public func createTextStreamResponse(
    status: Int? = nil,
    statusText: String? = nil,
    headers: [String: String]? = nil,
    textStream: AsyncThrowingStream<String, Error>
) -> TextStreamResponse {
    let preparedHeaders = prepareHeaders(
        headers,
        defaultHeaders: ["content-type": "text/plain; charset=utf-8"]
    )

    let responseInit = TextStreamResponseInit(
        headers: preparedHeaders,
        status: status ?? 200,
        statusText: statusText
    )

    return TextStreamResponse(stream: textStream, initOptions: responseInit)
}
