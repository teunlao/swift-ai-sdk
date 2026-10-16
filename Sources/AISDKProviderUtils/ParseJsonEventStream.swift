import Foundation
import EventSourceParser

/**
 Parses a JSON event stream (Server-Sent Events) into a stream of parsed JSON objects.

 Port of `@ai-sdk/provider-utils/src/parse-json-event-stream.ts`.

 This function:
 1. Decodes bytes to UTF-8 text
 2. Parses SSE events using EventSourceParser
 3. Ignores the `[DONE]` marker (OpenAI convention)
 4. Parses event data as JSON using the provided schema

 The result is pull-based: a source chunk is read only when no parsed event is
 pending, so the consumer paces the source and its cancellation reaches it.
 */
public func parseJsonEventStream<T>(
    stream: AsyncThrowingStream<Data, Error>,
    schema: FlexibleSchema<T>
) -> AsyncThrowingStream<ParseJSONResult<T>, Error> {
    let events = ServerSentEventReader(source: AsyncIteratorBox(stream.makeAsyncIterator()))

    return AsyncThrowingStream {
        while let event = try await events.next() {
            // Ignore the '[DONE]' event that e.g. OpenAI sends
            if event.data == "[DONE]" {
                continue
            }
            return await safeParseJSON(ParseJSONWithSchemaOptions(text: event.data, schema: schema))
        }
        return nil
    }
}

/// Reads server-sent events from a byte stream, one source chunk per empty event queue.
private final class ServerSentEventReader: @unchecked Sendable {
    private let source: AsyncIteratorBox<AsyncThrowingStream<Data, Error>.AsyncIterator>
    private var pending: [EventSourceMessage] = []
    private var isFinished = false
    private lazy var parser = EventSourceParser(callbacks: ParserCallbacks(
        onEvent: { [unowned self] event in self.pending.append(event) }
    ))

    init(source: AsyncIteratorBox<AsyncThrowingStream<Data, Error>.AsyncIterator>) {
        self.source = source
    }

    func next() async throws -> EventSourceMessage? {
        while pending.isEmpty {
            if isFinished {
                return nil
            }

            if let chunk = try await source.next() {
                parser.feed(chunk)
            } else {
                isFinished = true
                parser.reset(consume: true)
            }
        }

        return pending.removeFirst()
    }
}
