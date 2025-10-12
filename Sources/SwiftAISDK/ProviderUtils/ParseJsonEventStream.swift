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
 */
public func parseJsonEventStream<T>(
    stream: AsyncThrowingStream<Data, Error>,
    schema: FlexibleSchema<T>
) -> AsyncThrowingStream<ParseJSONResult<T>, Error> {
    AsyncThrowingStream { continuation in
        Task {
            do {
                // Use EventSourceParserStream to convert byte stream to SSE events
                let eventStream = EventSourceParserStream.makeStream(
                    from: stream,
                    options: EventSourceParserStreamOptions(onError: .ignore)
                )

                // Transform each event into a ParseJSONResult
                for try await event in eventStream {
                    // Ignore the '[DONE]' event that e.g. OpenAI sends
                    if event.data == "[DONE]" {
                        continue
                    }

                    let result = await safeParseJSON(
                        ParseJSONWithSchemaOptions(text: event.data, schema: schema)
                    )
                    continuation.yield(result)
                }

                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
}
