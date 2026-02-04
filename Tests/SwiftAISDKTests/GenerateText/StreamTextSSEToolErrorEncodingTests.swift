import AISDKProvider
import AISDKProviderUtils
import Foundation
import Testing

@testable import SwiftAISDK

@Suite("StreamText SSE – tool-error encoding")
struct StreamTextSSEToolErrorEncodingTests {
    private func decodeEvents(_ events: [String]) throws -> [NSDictionary] {
        try events.compactMap { line in
            guard line.hasPrefix("data: ") else { return nil }
            let jsonPart = String(line.dropFirst(6))
            let data = Data(jsonPart.utf8)
            let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            return object as? NSDictionary
        }
    }

    @Test("encodes tool-error providerMetadata")
    func encodesToolErrorProviderMetadata() async throws {
        let meta: ProviderMetadata = ["prov": ["tag": .string("m")]]

        let parts: [TextStreamPart] = [
            .toolError(.static(StaticToolError(
                toolCallId: "c1",
                toolName: "demo",
                title: "Demo Tool",
                input: .object(["q": .string("hi")]),
                error: NSError(domain: "x", code: 1),
                providerExecuted: true,
                providerMetadata: meta
            ))),
            .finish(finishReason: .stop, rawFinishReason: nil, totalUsage: LanguageModelUsage())
        ]

        let stream = AsyncThrowingStream<TextStreamPart, Error> { c in
            parts.forEach { c.yield($0) }
            c.finish()
        }

        let events = try await decodeEvents(convertReadableStreamToArray(makeStreamTextSSEStream(from: stream)))
        let toolError = try #require(events.first(where: { $0["type"] as? String == "tool-error" }))

        #expect(toolError["toolCallId"] as? String == "c1")
        #expect(toolError["toolName"] as? String == "demo")
        #expect(toolError["title"] as? String == "Demo Tool")
        #expect(toolError["providerExecuted"] as? Bool == true)

        let providerMetadata = toolError["providerMetadata"] as? NSDictionary
        #expect(providerMetadata?["prov"] != nil)
    }
}

