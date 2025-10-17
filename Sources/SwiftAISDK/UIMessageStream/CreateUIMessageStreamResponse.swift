import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Creates an HTTP-style response representation for a UI message stream.

 Port of `@ai-sdk/ai/src/ui-message-stream/create-ui-message-stream-response.ts`.
 */
public func createUIMessageStreamResponse<Message: UIMessageConvertible>(
    stream: AsyncThrowingStream<AnyUIMessageChunk, Error>,
    options: StreamTextUIResponseOptions<Message>? = nil
) -> UIMessageStreamResponse<Message> {
    var responseInit = options?.responseInit ?? UIMessageStreamResponseInit()
    let preparedHeaders = prepareHeaders(
        responseInit.headers,
        defaultHeaders: UI_MESSAGE_STREAM_HEADERS
    )
    responseInit.headers = preparedHeaders

    let responseStream = buildSSEStream(
        from: stream,
        consumer: responseInit.consumeSSEStream
    )

    // Mirror TypeScript behaviour: consumeSseStream executes immediately, so avoid re-running.
    responseInit.consumeSSEStream = nil

    let finalOptions = StreamTextUIResponseOptions(
        responseInit: responseInit,
        streamOptions: options?.streamOptions
    )

    return UIMessageStreamResponse(stream: responseStream, options: finalOptions)
}

/**
 Pipes a UI message stream into a streaming HTTP response writer.

 Port of `@ai-sdk/ai/src/ui-message-stream/pipe-ui-message-stream-to-response.ts`.
 */
public func pipeUIMessageStreamToResponse<Message: UIMessageConvertible>(
    response: any StreamTextResponseWriter,
    stream: AsyncThrowingStream<AnyUIMessageChunk, Error>,
    options: StreamTextUIResponseOptions<Message>? = nil
) {
    var responseInit = options?.responseInit ?? UIMessageStreamResponseInit()
    let preparedHeaders = prepareHeaders(
        responseInit.headers,
        defaultHeaders: UI_MESSAGE_STREAM_HEADERS
    )
    responseInit.headers = preparedHeaders

    response.writeHead(
        status: responseInit.status ?? 200,
        statusText: responseInit.statusText,
        headers: preparedHeaders.mapKeys { $0.lowercased() }
    )

    let sseStream = buildSSEStream(
        from: stream,
        consumer: responseInit.consumeSSEStream
    )

    responseInit.consumeSSEStream = nil

    Task {
        defer { response.end() }

        do {
            for try await chunk in sseStream {
                response.write(Data(chunk.utf8))
            }
        } catch {
            // Terminate the response silently, mirroring upstream behaviour.
        }
    }
}

// MARK: - Helpers

private func buildSSEStream(
    from chunkStream: AsyncThrowingStream<AnyUIMessageChunk, Error>,
    consumer: UIMessageStreamConsumer?
) -> AsyncThrowingStream<String, Error> {
    // Convert UI chunks → JSON → SSE
    let jsonStream = AsyncThrowingStream<JSONValue, Error> { continuation in
        let task = Task {
            do {
                for try await chunk in chunkStream {
                    continuation.yield(encodeUIMessageChunkToJSON(chunk))
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { termination in
            if case .cancelled = termination { task.cancel() }
        }
    }

    let sseBase = JsonToSSETransformStream().transform(stream: jsonStream)

    guard let consumer else {
        return sseBase
    }

    // Tie consumer lifetime to the returned stream to avoid leaked tasks.
    return AsyncThrowingStream { continuation in
        // Split base stream into producer (to caller) and consumer branch.
        let (producer, secondary) = teeAsyncThrowingStream(sseBase)

        // Kick off consumer immediately, as upstream.
        let consumerTask = Task {
            do {
                try await consumer(secondary)
            } catch {
                // Ignore consumer errors to mirror upstream behaviour.
            }
        }

        // Forward producer to the caller; cancel consumer when caller cancels.
        let forwardTask = Task {
            do {
                for try await chunk in producer {
                    continuation.yield(chunk)
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }

        continuation.onTermination = { termination in
            consumerTask.cancel()
            forwardTask.cancel()
        }
    }
}

private extension Dictionary where Key == String, Value == String {
    func mapKeys(_ transform: (String) -> String) -> [String: String] {
        reduce(into: [String: String]()) { result, entry in
            result[transform(entry.key)] = entry.value
        }
    }
}
