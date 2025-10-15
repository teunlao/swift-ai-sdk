/**
 UI message stream default headers.

 Port of `@ai-sdk/ai/src/ui-message-stream/ui-message-stream-headers.ts`.
 */
public let UI_MESSAGE_STREAM_HEADERS: [String: String] = [
    "content-type": "text/event-stream",
    "cache-control": "no-cache",
    "connection": "keep-alive",
    "x-vercel-ai-ui-message-stream": "v1",
    "x-accel-buffering": "no"
]

