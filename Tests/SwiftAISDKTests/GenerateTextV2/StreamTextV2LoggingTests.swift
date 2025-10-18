import Foundation
import Testing
@testable import SwiftAISDK
import AISDKProvider
import AISDKProviderUtils

@Suite("StreamTextV2 – logging")
struct StreamTextV2LoggingTests {
    private func sampleStream() -> AsyncThrowingStream<TextStreamPart, Error> {
        let usage = LanguageModelV3Usage(inputTokens: 1, outputTokens: 3, totalTokens: 4)
        let parts: [TextStreamPart] = [
            .start,
            .startStep(request: LanguageModelRequestMetadata(body: nil), warnings: []),
            .textDelta(id: "a", text: "Hi", providerMetadata: nil),
            .textEnd(id: "a", providerMetadata: nil),
            .finish(finishReason: .stop, totalUsage: usage)
        ]
        return AsyncThrowingStream { continuation in
            for part in parts { continuation.yield(part) }
            continuation.finish()
        }
    }

    @Test("log stream formats lines")
    func logStreamFormatsLines() async throws {
        let stream = sampleStream()
        let logs = try await convertReadableStreamToArray(makeStreamTextV2LogStream(from: stream))
        #expect(logs.contains { $0.contains("stream:start") })
        #expect(logs.contains { $0.contains("text[a] += Hi") })
        #expect(logs.contains { $0.contains("stream:finish") })
    }

    @Test("log function forwards to callback with timestamps")
    func logFunctionForwardsLines() async throws {
        let stream = sampleStream()
        let (lineStream, continuation) = AsyncStream.makeStream(of: String.self)
        let options = StreamTextV2LogOptions(includeTimestamps: true, clock: { Date(timeIntervalSince1970: 0) })
        try await logStreamTextV2Events(from: stream, options: options) { line in
            continuation.yield(line)
        }
        continuation.finish()
        var received: [String] = []
        for await line in lineStream {
            received.append(line)
        }
        #expect(!received.isEmpty)
        #expect(received.first?.contains("0.000") == true)
    }

    @Test("log stream preserves prefix")
    func logStreamPreservesPrefix() async throws {
        let stream = sampleStream()
        let options = StreamTextV2LogOptions(prefix: "[test]")
        let logs = try await convertReadableStreamToArray(makeStreamTextV2LogStream(from: stream, options: options))
        #expect(logs.allSatisfy { $0.hasPrefix("[test]") })
    }
}
