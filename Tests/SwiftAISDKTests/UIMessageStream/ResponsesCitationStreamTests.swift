import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import OpenAIProvider
import SwiftAISDK

@Suite("Responses citations through UI transport")
struct ResponsesCitationStreamTests {
    @Test("Provider citation offsets survive streamText and public SSE encoding")
    func citationTransport() async throws {
        let events: [JSONValue] = [
            .object(["type": .string("response.output_item.added"), "output_index": .number(0.5), "item": .object(["type": .string("message"), "id": .string("message")])]),
            .object(["type": .string("response.output_text.delta"), "output_index": .number(0.5), "item_id": .string("rotated_delta"), "delta": .string("answer")]),
            .object(["type": .string("response.output_text.annotation.added"), "annotation": .object([
                "type": .string("url_citation"), "url": .string("https://proof.test"), "title": .string("Proof"), "start_index": .number(0.5), "end_index": .number(1e20)
            ])]),
            .object(["type": .string("response.output_item.done"), "output_index": .number(0.5), "item": .object(["type": .string("message"), "id": .string("rotated_done")])]),
            .object(["type": .string("response.completed"), "response": .object([:])])
        ]
        let payload = Data(try events.map { "data: \(String(decoding: try JSONEncoder().encode($0), as: UTF8.self))\n\n" }.joined().utf8)
        let provider = try createOpenAI(settings: .init(apiKey: "test", fetch: { request in
            FetchResponse(body: .data(payload), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!)
        }))
        let result = try streamText(model: provider.responses("gpt-6"), prompt: "question")
        let response: UIMessageStreamResponse<UIMessage> = try result.toUIMessageStreamResponse(options: nil)
        var textEnd: [String: JSONValue]?
        for try await chunk in response.stream {
            for line in chunk.split(separator: "\n") where line.hasPrefix("data: ") && line != "data: [DONE]" {
                let value = try JSONDecoder().decode(JSONValue.self, from: Data(line.dropFirst(6).utf8))
                if case .object(let object) = value, object["type"] == .string("text-end") { textEnd = object }
            }
        }
        let end = try #require(textEnd)
        guard case .array(let citations)? = end["citations"], citations.count == 1, case .object(let citation) = citations[0], case .object(let source)? = citation["source"] else {
            Issue.record("Citation disappeared before UI transport"); return
        }
        #expect(citation["startIndex"] == .number(0.5))
        #expect(citation["endIndex"] == .number(1e20))
        #expect(source["id"] == .string("https://proof.test") && source["url"] == .string("https://proof.test"))
    }
}
