import AISDKProvider
import AISDKProviderUtils
import Foundation
import Testing

@testable import SwiftAISDK

@Suite("StreamText SSE – tool-input encoding")
struct StreamTextSSEToolInputEncodingTests {

    private func decodeEvents(_ events: [String]) throws -> [NSDictionary] {
        try events.compactMap { line in
            guard line.hasPrefix("data: ") else { return nil }
            let jsonPart = String(line.dropFirst(6))
            let data = Data(jsonPart.utf8)
            let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            return object as? NSDictionary
        }
    }

    @Test("tool-input-start uses toolName key (not name)")
    func toolInputStartUsesToolNameKey() async throws {
        let parts: [TextStreamPart] = [
            .toolInputStart(
                id: "c1",
                toolName: "demo",
                providerMetadata: nil,
                providerExecuted: false,
                dynamic: nil,
                title: "Demo Tool"
            ),
            .finish(finishReason: .stop, rawFinishReason: nil, totalUsage: LanguageModelUsage())
        ]

        let stream = AsyncThrowingStream<TextStreamPart, Error> { c in
            parts.forEach { c.yield($0) }
            c.finish()
        }

        let events = try await decodeEvents(convertReadableStreamToArray(makeStreamTextSSEStream(from: stream)))
        let inputStart = try #require(events.first(where: { $0["type"] as? String == "tool-input-start" }))

        #expect(inputStart["toolName"] as? String == "demo")
        #expect(inputStart["name"] == nil)
        #expect(inputStart["title"] as? String == "Demo Tool")
    }
}
