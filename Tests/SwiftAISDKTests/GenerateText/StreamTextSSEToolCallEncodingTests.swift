import AISDKProvider
import AISDKProviderUtils
import Foundation
import Testing

@testable import SwiftAISDK

@Suite("StreamText SSE – tool-call encoding")
struct StreamTextSSEToolCallEncodingTests {

    private func decodeEvents(_ events: [String]) throws -> [NSDictionary] {
        try events.compactMap { line in
            guard line.hasPrefix("data: ") else { return nil }
            let jsonPart = String(line.dropFirst(6))
            let data = Data(jsonPart.utf8)
            let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            return object as? NSDictionary
        }
    }

    @Test("encodes static tool-call providerMetadata and title")
    func encodesStaticToolCallMetadataAndTitle() async throws {
        let meta: ProviderMetadata = ["prov": ["tag": .string("m")]]
        let parts: [TextStreamPart] = [
            .toolCall(.static(StaticToolCall(
                toolCallId: "c1",
                toolName: "demo",
                title: "Demo Tool",
                input: .object(["q": .string("hi")]),
                providerExecuted: false,
                providerMetadata: meta
            ))),
            .finish(finishReason: .stop, totalUsage: LanguageModelUsage())
        ]

        let stream = AsyncThrowingStream<TextStreamPart, Error> { c in
            parts.forEach { c.yield($0) }
            c.finish()
        }

        let events = try await decodeEvents(convertReadableStreamToArray(makeStreamTextSSEStream(from: stream)))
        let toolCall = try #require(events.first(where: { $0["type"] as? String == "tool-call" }))

        #expect(toolCall["toolCallId"] as? String == "c1")
        #expect(toolCall["toolName"] as? String == "demo")
        #expect(toolCall["title"] as? String == "Demo Tool")
        #expect(toolCall["providerExecuted"] as? Bool == false)

        let providerMetadata = toolCall["providerMetadata"] as? NSDictionary
        #expect(providerMetadata?["prov"] != nil)
    }

    @Test("encodes dynamic tool-call error, invalid, dynamic and title")
    func encodesDynamicToolCallFields() async throws {
        let meta: ProviderMetadata = ["prov": ["tag": .string("m")]]
        let err = NSError(domain: "x", code: 1, userInfo: [NSLocalizedDescriptionKey: "boom"])

        let parts: [TextStreamPart] = [
            .toolCall(.dynamic(DynamicToolCall(
                toolCallId: "c2",
                toolName: "missing",
                title: "Missing Tool",
                input: .string("raw"),
                providerExecuted: nil,
                providerMetadata: meta,
                invalid: true,
                error: err
            ))),
            .finish(finishReason: .stop, totalUsage: LanguageModelUsage())
        ]

        let stream = AsyncThrowingStream<TextStreamPart, Error> { c in
            parts.forEach { c.yield($0) }
            c.finish()
        }

        let events = try await decodeEvents(convertReadableStreamToArray(makeStreamTextSSEStream(from: stream)))
        let toolCall = try #require(events.first(where: { $0["type"] as? String == "tool-call" }))

        #expect(toolCall["toolCallId"] as? String == "c2")
        #expect(toolCall["toolName"] as? String == "missing")
        #expect(toolCall["title"] as? String == "Missing Tool")
        #expect(toolCall["dynamic"] as? Bool == true)
        #expect(toolCall["invalid"] as? Bool == true)

        let errValue = toolCall["error"] as? String
        #expect(errValue?.isEmpty == false)

        let providerMetadata = toolCall["providerMetadata"] as? NSDictionary
        #expect(providerMetadata?["prov"] != nil)
    }
}
