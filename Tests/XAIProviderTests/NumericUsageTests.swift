import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import XAIProvider

@Suite("xAI numeric usage boundaries")
struct NumericUsageTests {
    private let prompt: LanguageModelV4Prompt = [.user(content: [.text(.init(text: "hello"))], providerOptions: nil)]

    private func model(usage: JSONValue, streaming: Bool = false) throws -> XAIResponsesLanguageModel {
        let body: JSONValue = .object([
            "id": .string("response"), "object": .string("response"), "status": .string("completed"),
            "output": .array([.object(["id": .string("message"), "type": .string("message"), "role": .string("assistant"), "status": .string("completed"), "content": .array([.object(["type": .string("output_text"), "text": .string("answer"), "annotations": .array([])])])])]),
            "usage": usage
        ])
        let data: Data
        if streaming {
            let events: [JSONValue] = [
                .object(["type": .string("response.content_part.added"), "item_id": .string("message"), "output_index": .number(0), "content_index": .number(0), "part": .object(["type": .string("output_text"), "text": .string("")])]),
                .object(["type": .string("response.output_text.delta"), "item_id": .string("message"), "output_index": .number(0), "content_index": .number(0), "delta": .string("answer")]),
                .object(["type": .string("response.completed"), "response": body])
            ]
            data = Data(try events.map { "data: \(String(decoding: try JSONEncoder().encode($0), as: UTF8.self))\n\n" }.joined().utf8)
        } else {
            data = try JSONEncoder().encode(body)
        }
        return createXai(settings: .init(baseURL: "https://api.example.test/v1", apiKey: "test-key", fetch: { request in
            let response = try #require(HTTPURLResponse(url: #require(request.url), statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": streaming ? "text/event-stream" : "application/json"]))
            return FetchResponse(body: .data(data), urlResponse: response)
        })).responses("grok-4")
    }

    @Test("Numeric anomalies preserve generated and streamed output with raw usage", arguments: [false, true])
    func anomalousCounts(_ streaming: Bool) async throws {
        let raw: JSONValue = .object([
            "input_tokens": .number(1.5), "output_tokens": .number(1e100), "total_tokens": .number(1e100),
            "input_tokens_details": .object(["cached_tokens": .number(1.5), "future_count": .number(3)]),
            "output_tokens_details": .object(["reasoning_tokens": .number(1e100), "future_count": .number(4)]),
            "num_sources_used": .number(1.5), "num_server_side_tools_used": .number(1e100), "future_count": .number(7)
        ])
        let model = try model(usage: raw, streaming: streaming)
        let usage: LanguageModelV4Usage
        if streaming {
            let result = try await model.doStream(options: .init(prompt: prompt))
            let parts = try await convertReadableStreamToArray(result.stream)
            let text = parts.compactMap { part -> String? in
                if case .textDelta(_, let delta, _) = part { return delta }
                return nil
            }.joined()
            #expect(text == "answer")
            guard case .finish(_, let value, _)? = parts.last else { Issue.record("Expected finish"); return }
            usage = value
        } else {
            let result = try await model.doGenerate(options: .init(prompt: prompt))
            #expect(result.content == [.text(.init(text: "answer"))])
            usage = result.usage
        }
        #expect(usage.inputTokens.total == nil)
        #expect(usage.inputTokens.noCache == nil)
        #expect(usage.inputTokens.cacheRead == nil)
        #expect(usage.outputTokens.total == nil)
        #expect(usage.outputTokens.text == nil)
        #expect(usage.outputTokens.reasoning == nil)
        #expect(usage.raw == raw)
    }

    @Test("Missing details default to zero while invalid present details remain unknown", arguments: [false, true])
    func detailCounts(_ invalid: Bool) async throws {
        var raw: [String: JSONValue] = ["input_tokens": .number(10), "output_tokens": .number(20)]
        if invalid {
            raw["input_tokens_details"] = .object(["cached_tokens": .number(1.5)])
            raw["output_tokens_details"] = .object(["reasoning_tokens": .number(1e100)])
        }
        let usage = try await model(usage: .object(raw)).doGenerate(options: .init(prompt: prompt)).usage
        #expect(usage.inputTokens.total == (invalid ? nil : 10))
        #expect(usage.inputTokens.noCache == (invalid ? nil : 10))
        #expect(usage.inputTokens.cacheRead == (invalid ? nil : 0))
        #expect(usage.outputTokens.total == 20)
        #expect(usage.outputTokens.text == (invalid ? nil : 20))
        #expect(usage.outputTokens.reasoning == (invalid ? nil : 0))
        #expect(usage.raw == .object(raw))
    }

    @Test("Inclusive subtraction and exclusive cached-token addition cannot overflow", arguments: [false, true])
    func overflow(_ exclusiveCache: Bool) async throws {
        let raw: JSONValue = .object([
            "input_tokens": .number(exclusiveCache ? 8e18 : 9e18), "output_tokens": .number(9e18),
            "input_tokens_details": .object(["cached_tokens": .number(exclusiveCache ? 9e18 : -9e18)]),
            "output_tokens_details": .object(["reasoning_tokens": .number(-9e18)])
        ])
        let usage = try await model(usage: raw).doGenerate(options: .init(prompt: prompt)).usage
        let expectedTotal: Int? = exclusiveCache ? nil : 9_000_000_000_000_000_000
        let expectedNoCache: Int? = exclusiveCache ? 8_000_000_000_000_000_000 : nil
        #expect(usage.inputTokens.total == expectedTotal)
        #expect(usage.inputTokens.noCache == expectedNoCache)
        #expect(usage.outputTokens.total == 9_000_000_000_000_000_000)
        #expect(usage.outputTokens.text == nil)
        #expect(usage.raw == raw)
    }

    @Test("Nonnumeric nested usage retains a typed response failure")
    func malformedCount() async throws {
        let raw: JSONValue = .object(["input_tokens": .number(10), "output_tokens": .number(20), "input_tokens_details": .object(["cached_tokens": .string("invalid")])])
        let model = try model(usage: raw)
        await #expect(throws: APICallError.self) { _ = try await model.doGenerate(options: .init(prompt: prompt)) }
    }
}
