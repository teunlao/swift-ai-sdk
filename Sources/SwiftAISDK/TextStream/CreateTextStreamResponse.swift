import Foundation

/**
 Creates a `TextStreamResponse` with UTF-8 encoded text stream defaults.

 Port of `@ai-sdk/ai/src/text-stream/create-text-stream-response.ts`.
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
