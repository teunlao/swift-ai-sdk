import Foundation
import AISDKProvider
import AISDKProviderUtils

public func createUIMessageStreamResponse<Message: UIMessageConvertible>(
    stream: AsyncThrowingStream<AnyUIMessageChunk, Error>,
    options: StreamTextUIResponseOptions<Message>? = nil
) throws -> UIMessageStreamResponse<Message> {
    var responseInit = options?.responseInit ?? UIMessageStreamResponseInit()
    let responseStream = try buildSSEStream(
        from: stream, consumer: responseInit.consumeSSEStream, keepAliveMs: responseInit.keepAliveMs
    )
    responseInit.headers = prepareHeaders(responseInit.headers, defaultHeaders: UI_MESSAGE_STREAM_HEADERS)
    responseInit.consumeSSEStream = nil
    return UIMessageStreamResponse(stream: responseStream, options: StreamTextUIResponseOptions(
        responseInit: responseInit, streamOptions: options?.streamOptions
    ))
}

public func pipeUIMessageStreamToResponse<Message: UIMessageConvertible>(
    response: any StreamTextResponseWriter,
    stream: AsyncThrowingStream<AnyUIMessageChunk, Error>,
    options: StreamTextUIResponseOptions<Message>? = nil
) async throws {
    let responseInit = options?.responseInit ?? UIMessageStreamResponseInit()
    let sseStream = try buildSSEStream(
        from: stream, consumer: responseInit.consumeSSEStream, keepAliveMs: responseInit.keepAliveMs
    )
    let headers = prepareHeaders(responseInit.headers, defaultHeaders: UI_MESSAGE_STREAM_HEADERS)
    response.writeHead(status: responseInit.status ?? 200, statusText: responseInit.statusText,
                       headers: headers.mapKeys { $0.lowercased() })
    try await writeToServerResponse(response: response, stream: sseStream)
}

private func buildSSEStream(
    from chunkStream: AsyncThrowingStream<AnyUIMessageChunk, Error>,
    consumer: UIMessageStreamConsumer?, keepAliveMs: Double?
) throws -> AsyncThrowingStream<String, Error> {
    let source = createAsyncIterableStream(source: chunkStream)
    let iterator = source.makeAsyncIterator()
    let jsonStream = AsyncThrowingStream<JSONValue, Error>(unfolding: {
        try await withTaskCancellationHandler {
            guard let chunk = try await iterator.next() else { return nil }
            return encodeUIMessageChunkToJSON(chunk)
        } onCancel: {
            Task { await source.cancel() }
        }
    })
    let stream = try createSSEStreamWithKeepAlive(
        stream: JsonToSSETransformStream().transform(stream: jsonStream), keepAliveMs: keepAliveMs
    )
    guard let consumer else { return stream }
    let (response, secondary) = teeAsyncThrowingStream(stream)
    Task {
        do { try await consumer(secondary) }
        catch { /* The independent observer cannot fail the response. */ }
    }
    return response
}

private extension Dictionary where Key == String, Value == String {
    func mapKeys(_ transform: (String) -> String) -> [String: String] {
        reduce(into: [:]) { result, entry in result[transform(entry.key)] = entry.value }
    }
}
