import AISDKProvider
import AISDKProviderUtils
import Foundation
import Testing

@testable import SwiftAISDK

@Suite("StreamText SSE – tool approval encoding")
struct StreamTextSSEToolApprovalEncodingTests {

    private func decodeEvents(_ events: [String]) throws -> [NSDictionary] {
        try events.compactMap { line in
            guard line.hasPrefix("data: ") else { return nil }
            let jsonPart = String(line.dropFirst(6))
            let data = Data(jsonPart.utf8)
            let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            return object as? NSDictionary
        }
    }

    @Test("tool-approval-request includes toolCallId, toolName, title and input")
    func toolApprovalRequestIncludesFields() async throws {
        let meta: ProviderMetadata = ["prov": ["tag": .string("m")]]
        let call = TypedToolCall.static(StaticToolCall(
            toolCallId: "c1",
            toolName: "demo",
            title: "Demo Tool",
            input: .object(["q": .string("hi")]),
            providerExecuted: false,
            providerMetadata: meta
        ))

        let parts: [TextStreamPart] = [
            .toolApprovalRequest(ToolApprovalRequestOutput(approvalId: "a1", toolCall: call)),
            .finish(finishReason: .stop, rawFinishReason: nil, totalUsage: LanguageModelUsage())
        ]

        let stream = AsyncThrowingStream<TextStreamPart, Error> { c in
            parts.forEach { c.yield($0) }
            c.finish()
        }

        let events = try await decodeEvents(convertReadableStreamToArray(makeStreamTextSSEStream(from: stream)))
        let approval = try #require(events.first(where: { $0["type"] as? String == "tool-approval-request" }))

        #expect(approval["approvalId"] as? String == "a1")
        #expect(approval["toolCallId"] as? String == "c1")
        #expect(approval["toolName"] as? String == "demo")
        #expect(approval["title"] as? String == "Demo Tool")
        #expect((approval["providerMetadata"] as? NSDictionary)?["prov"] != nil)

        let input = approval["input"] as? NSDictionary
        #expect(input?["q"] as? String == "hi")
    }
}
