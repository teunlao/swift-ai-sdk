import Testing
import AISDKProvider
@testable import SwiftAISDK

@Suite("JsonToSSETransformStream")
struct JsonToSSETransformStreamTests {
    @Test("encodes JSON values into SSE frames")
    func encodesValues() async throws {
        let transform = JsonToSSETransformStream()
        let input: [JSONValue] = [
            .object(["type": .string("text-delta"), "delta": .string("hi")]),
            .object(["type": .string("finish")])
        ]

        let stream: AsyncThrowingStream<JSONValue, Error> = makeAsyncStream(from: input)
        let resultStream = transform.transform(stream: stream)
        let chunks: [String] = try await collectStream(resultStream)

        #expect(chunks.count == 3)
        #expect(chunks[0] == "data: {\"delta\":\"hi\",\"type\":\"text-delta\"}\n\n")
        #expect(chunks[1] == "data: {\"type\":\"finish\"}\n\n")
        #expect(chunks[2] == "data: [DONE]\n\n")
    }
}
