import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import OpenAIProvider

@Suite("OpenAI numeric usage boundaries")
struct NumericUsageTests {
    private let prompt: LanguageModelV4Prompt = [.user(content: [.text(.init(text: "hello"))], providerOptions: nil)]

    private func fetch(_ kind: String, usage: JSONValue, streaming: Bool = false) throws -> FetchFunction {
        let body: JSONValue
        if kind == "embedding" {
            body = .object(["data": .array([.object(["embedding": .array([.number(0.25)])])]), "usage": usage])
        } else {
            var choice: [String: JSONValue] = ["index": .number(0), "finish_reason": .string("stop")]
            if kind == "chat" {
                choice[streaming ? "delta" : "message"] = .object(["role": .string("assistant"), "content": .string("answer")])
            } else {
                choice["text"] = .string("answer")
            }
            body = .object(["choices": .array([.object(choice)]), "usage": usage])
        }
        let encoded = try JSONEncoder().encode(body)
        let data = streaming ? Data("data: \(String(decoding: encoded, as: UTF8.self))\n\ndata: [DONE]\n\n".utf8) : encoded
        return { request in
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": streaming ? "text/event-stream" : "application/json"]))
            return FetchResponse(body: .data(data), urlResponse: response)
        }
    }

    private func model(_ kind: String, usage: JSONValue, streaming: Bool = false) throws -> any LanguageModelV4 {
        let provider = try createOpenAI(settings: .init(baseURL: "https://api.example.test/v1", apiKey: "test-key", fetch: fetch(kind, usage: usage, streaming: streaming)))
        if kind == "chat" { return provider.chat("gpt-4o-mini") }
        return provider.completion("gpt-3.5-turbo-instruct")
    }

    @Test("Numeric anomalies retain generated and streamed output and complete raw usage", arguments: [("chat", false), ("chat", true), ("completion", false), ("completion", true)])
    func anomalousCounts(_ kind: String, _ streaming: Bool) async throws {
        let raw: JSONValue = .object(["prompt_tokens": .number(1.5), "completion_tokens": .number(1e100), "total_tokens": .number(1e100), "future_count": .number(7)])
        let model = try model(kind, usage: raw, streaming: streaming)
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
        #expect(usage.outputTokens.total == nil)
        #expect(usage.outputTokens.text == nil)
        #expect(usage.raw == raw)
    }

    @Test("Missing chat details default to zero while invalid present details remain unknown", arguments: [false, true])
    func detailCounts(_ invalid: Bool) async throws {
        var raw: [String: JSONValue] = ["prompt_tokens": .number(10), "completion_tokens": .number(20)]
        if invalid {
            raw["prompt_tokens_details"] = .object(["cached_tokens": .number(1.5), "cache_write_tokens": .number(1e100), "future_count": .number(3)])
            raw["completion_tokens_details"] = .object(["reasoning_tokens": .number(1e100), "accepted_prediction_tokens": .number(1.5), "rejected_prediction_tokens": .number(1e100), "future_count": .number(4)])
        }
        let result = try await model("chat", usage: .object(raw)).doGenerate(options: .init(prompt: prompt))
        #expect(result.usage.inputTokens.total == 10)
        #expect(result.usage.inputTokens.noCache == (invalid ? nil : 10))
        #expect(result.usage.inputTokens.cacheRead == (invalid ? nil : 0))
        #expect(result.usage.inputTokens.cacheWrite == nil)
        #expect(result.usage.outputTokens.total == 20)
        #expect(result.usage.outputTokens.text == (invalid ? nil : 20))
        #expect(result.usage.outputTokens.reasoning == (invalid ? nil : 0))
        #expect(result.usage.raw == .object(raw))
    }

    @Test("Chat derived usage cannot overflow")
    func overflow() async throws {
        let raw: JSONValue = .object(["prompt_tokens": .number(9e18), "completion_tokens": .number(9e18), "prompt_tokens_details": .object(["cached_tokens": .number(-9e18)]), "completion_tokens_details": .object(["reasoning_tokens": .number(-9e18)])])
        let usage = try await model("chat", usage: raw).doGenerate(options: .init(prompt: prompt)).usage
        #expect(usage.inputTokens.total == 9_000_000_000_000_000_000)
        #expect(usage.inputTokens.noCache == nil)
        #expect(usage.outputTokens.total == 9_000_000_000_000_000_000)
        #expect(usage.outputTokens.text == nil)
        #expect(usage.raw == raw)
    }

    @Test("Embedding anomalies preserve vectors and raw usage", arguments: [1.5, 1e100])
    func embedding(_ count: Double) async throws {
        let raw: JSONValue = .object(["prompt_tokens": .number(count), "future_count": .number(7)])
        let provider = try createOpenAI(settings: .init(baseURL: "https://api.example.test/v1", apiKey: "test-key", fetch: fetch("embedding", usage: raw)))
        let result = try await provider.embedding("text-embedding-3-small").doEmbed(options: .init(values: ["text"]))
        #expect(result.embeddings == [[0.25]])
        #expect(result.usage?.tokens == nil)
        let body = try jsonValue(from: #require(result.response?.body))
        guard case .object(let object) = body else { Issue.record("Expected raw response"); return }
        #expect(object["usage"] == raw)
    }

    @Test("Nonnumeric usage retains typed failures", arguments: ["chat", "completion", "embedding"])
    func malformedCounts(_ kind: String) async throws {
        let raw: JSONValue = kind == "chat"
            ? .object(["prompt_tokens": .number(1), "prompt_tokens_details": .object(["cached_tokens": .string("invalid")])])
            : .object(["prompt_tokens": .string("invalid"), "completion_tokens": .number(1), "total_tokens": .number(2)])
        if kind == "embedding" {
            let provider = try createOpenAI(settings: .init(baseURL: "https://api.example.test/v1", apiKey: "test-key", fetch: fetch(kind, usage: raw)))
            await #expect(throws: APICallError.self) { _ = try await provider.embedding("text-embedding-3-small").doEmbed(options: .init(values: ["text"])) }
        } else {
            let model = try model(kind, usage: raw)
            await #expect(throws: APICallError.self) { _ = try await model.doGenerate(options: .init(prompt: prompt)) }
        }
    }
}
