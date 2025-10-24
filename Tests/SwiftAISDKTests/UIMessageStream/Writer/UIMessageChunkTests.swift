import AISDKProvider
import Testing
@testable import SwiftAISDK

/**
 Tests for UI message stream chunk infrastructure.

 Mirrors runtime expectations from
 `@ai-sdk/ai/src/ui-message-stream/ui-message-chunks.ts`.
 */
@Suite("UI Message Chunk Tests")
struct UIMessageChunkTests {

    @Test("detects data-* chunks")
    func detectsDataChunks() throws {
        let dataChunk = AnyUIMessageChunk.data(
            DataUIMessageChunk(name: "custom", id: "chunk-1", data: ["value": 42], transient: true)
        )
        let textChunk = AnyUIMessageChunk.textStart(id: "message-1", providerMetadata: nil)

        #expect(isDataUIMessageChunk(dataChunk))
        #expect(!isDataUIMessageChunk(textChunk))
    }

    @Test("computes type identifiers")
    func computesTypeIdentifiers() throws {
        let errorChunk = UIMessageChunk<JSONValue>.toolOutputError(
            toolCallId: "tool-1",
            errorText: "boom",
            providerExecuted: true,
            dynamic: false
        )
        #expect(errorChunk.typeIdentifier == "tool-output-error")

        let dataChunk = AnyUIMessageChunk.data(
            DataUIMessageChunk(name: "payload", data: ["foo": "bar"])
        )
        #expect(dataChunk.typeIdentifier == "data-payload")
    }

    @Test("matches default stream headers")
    func matchesDefaultHeaders() throws {
        let expected: [String: String] = [
            "content-type": "text/event-stream",
            "cache-control": "no-cache",
            "connection": "keep-alive",
            "x-vercel-ai-ui-message-stream": "v1",
            "x-accel-buffering": "no"
        ]

        #expect(UI_MESSAGE_STREAM_HEADERS == expected)
    }
}
