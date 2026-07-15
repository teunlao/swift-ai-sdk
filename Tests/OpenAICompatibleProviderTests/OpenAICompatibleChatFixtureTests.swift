import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import OpenAICompatibleProvider

private let fixturePrompt: LanguageModelV4Prompt = [
    .user(
        content: [.text(LanguageModelV4TextPart(text: "Hello"))],
        providerOptions: nil
    )
]

@Suite("OpenAI-compatible upstream chat fixtures")
struct OpenAICompatibleChatFixtureTests {
    private func fixtureURL(_ name: String, extension fileExtension: String) throws -> URL {
        try #require(Bundle.module.url(
            forResource: name,
            withExtension: fileExtension,
            subdirectory: "Fixtures"
        ))
    }

    private func fixtureData(_ name: String) throws -> Data {
        try Data(contentsOf: fixtureURL(name, extension: "json"))
    }

    private func fixtureEvents(_ name: String) throws -> [String] {
        let contents = try String(
            contentsOf: fixtureURL(name, extension: "chunks.txt"),
            encoding: .utf8
        )
        return contents.split(whereSeparator: \.isNewline).map(String.init)
    }

    private func makeHTTPResponse(contentType: String) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://my.api.com/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": contentType]
        )!
    }

    private func makeStreamBody(_ events: [String]) -> ProviderHTTPResponseBody {
        .stream(AsyncThrowingStream { continuation in
            for event in events {
                continuation.yield(Data("data: \(event)\n\n".utf8))
            }
            continuation.yield(Data("data: [DONE]\n\n".utf8))
            continuation.finish()
        })
    }

    private func makeModel(fetch: @escaping FetchFunction) throws -> any LanguageModelV4 {
        let provider = createOpenAICompatible(settings: .init(
            baseURL: "https://my.api.com/v1",
            name: "test-provider",
            fetch: fetch
        ))
        return try provider.languageModel(modelId: "grok-3")
    }

    @Test("generates text reasoning usage and metadata from the upstream XAI fixture")
    func generatesTextFixture() async throws {
        let data = try fixtureData("xai-text")
        let fetch: FetchFunction = { _ in
            FetchResponse(
                body: .data(data),
                urlResponse: makeHTTPResponse(contentType: "application/json")
            )
        }
        let model = try makeModel(fetch: fetch)
        let result = try await model.doGenerate(options: .init(prompt: fixturePrompt))

        #expect(result.finishReason == .init(unified: .stop, raw: "stop"))
        #expect(result.content.count == 2)
        guard case let .text(text) = result.content[0],
              case let .reasoning(reasoning) = result.content[1] else {
            Issue.record("Expected fixture text followed by reasoning")
            return
        }
        #expect(text.text == "Grok")
        #expect(reasoning.text.hasPrefix("First, the user said:"))
        #expect(reasoning.text.hasSuffix("So, my response will be: Grok"))
        #expect(result.usage.inputTokens.total == 12)
        #expect(result.usage.inputTokens.noCache == 10)
        #expect(result.usage.inputTokens.cacheRead == 2)
        #expect(result.usage.outputTokens.total == 2)
        #expect(result.usage.outputTokens.reasoning == 320)
        #expect(result.usage.outputTokens.text == -318)
        guard case let .object(rawUsage)? = result.usage.raw else {
            Issue.record("Expected complete raw fixture usage")
            return
        }
        #expect(rawUsage["num_sources_used"] == .number(0))
        #expect(rawUsage["cost_in_usd_ticks"] == .number(1_641_500))
        #expect(result.response?.id == "edea4703-19aa-6d74-fedb-dc1c213543e0")
        #expect(result.response?.modelId == "grok-3-mini")
        #expect(result.response?.timestamp == Date(timeIntervalSince1970: 1_770_772_090))
    }

    @Test("generates a tool call and reasoning from the upstream XAI fixture")
    func generatesToolCallFixture() async throws {
        let data = try fixtureData("xai-tool-call")
        let fetch: FetchFunction = { _ in
            FetchResponse(
                body: .data(data),
                urlResponse: makeHTTPResponse(contentType: "application/json")
            )
        }
        let model = try makeModel(fetch: fetch)
        let result = try await model.doGenerate(options: .init(prompt: fixturePrompt))

        #expect(result.finishReason == .init(unified: .toolCalls, raw: "tool_calls"))
        #expect(result.content.count == 2)
        guard case let .reasoning(reasoning) = result.content[0],
              case let .toolCall(toolCall) = result.content[1] else {
            Issue.record("Expected fixture reasoning followed by a tool call")
            return
        }
        #expect(reasoning.text.hasPrefix("First, the user is asking about the weather"))
        #expect(toolCall.toolCallId == "call_46427107")
        #expect(toolCall.toolName == "weather")
        #expect(toolCall.input == #"{"location":"San Francisco"}"#)
        #expect(result.usage.inputTokens.total == 307)
        #expect(result.usage.inputTokens.noCache == 63)
        #expect(result.usage.inputTokens.cacheRead == 244)
        #expect(result.usage.outputTokens.total == 26)
        #expect(result.usage.outputTokens.reasoning == 255)
        #expect(result.usage.outputTokens.text == -229)
    }

    @Test("streams text lifecycle and usage from all upstream XAI chunks")
    func streamsTextFixture() async throws {
        let events = try fixtureEvents("xai-text")
        #expect(events.count == 344)
        let fetch: FetchFunction = { _ in
            FetchResponse(
                body: makeStreamBody(events),
                urlResponse: makeHTTPResponse(contentType: "text/event-stream")
            )
        }
        let model = try makeModel(fetch: fetch)
        let result = try await model.doStream(options: .init(prompt: fixturePrompt))

        var parts: [LanguageModelV4StreamPart] = []
        for try await part in result.stream {
            parts.append(part)
        }

        let reasoning = parts.compactMap { part -> String? in
            if case let .reasoningDelta(_, delta, _) = part { return delta }
            return nil
        }.joined()
        let text = parts.compactMap { part -> String? in
            if case let .textDelta(_, delta, _) = part { return delta }
            return nil
        }.joined()
        #expect(reasoning.hasPrefix("First, the user said:"))
        #expect(reasoning.hasSuffix("Response: Grok"))
        #expect(text == "Grok")
        #expect(parts.filter { if case .reasoningStart = $0 { return true }; return false }.count == 1)
        #expect(parts.filter { if case .reasoningEnd = $0 { return true }; return false }.count == 1)
        #expect(parts.filter { if case .textStart = $0 { return true }; return false }.count == 1)
        #expect(parts.filter { if case .textEnd = $0 { return true }; return false }.count == 1)

        guard case let .finish(finishReason, usage, _) = parts.last else {
            Issue.record("Expected fixture stream finish")
            return
        }
        #expect(finishReason == .init(unified: .stop, raw: "stop"))
        #expect(usage.inputTokens.total == 12)
        #expect(usage.inputTokens.noCache == 1)
        #expect(usage.inputTokens.cacheRead == 11)
        #expect(usage.outputTokens.total == 2)
        #expect(usage.outputTokens.reasoning == 340)
        #expect(usage.outputTokens.text == -338)
        guard case let .object(rawUsage)? = usage.raw else {
            Issue.record("Expected complete raw stream usage")
            return
        }
        #expect(rawUsage["cost_in_usd_ticks"] == .number(1_721_250))
    }

    @Test("streams reasoning and a complete tool call from all upstream XAI chunks")
    func streamsToolCallFixture() async throws {
        let events = try fixtureEvents("xai-tool-call")
        #expect(events.count == 230)
        let fetch: FetchFunction = { _ in
            FetchResponse(
                body: makeStreamBody(events),
                urlResponse: makeHTTPResponse(contentType: "text/event-stream")
            )
        }
        let model = try makeModel(fetch: fetch)
        let result = try await model.doStream(options: .init(prompt: fixturePrompt))

        var parts: [LanguageModelV4StreamPart] = []
        for try await part in result.stream {
            parts.append(part)
        }

        let reasoning = parts.compactMap { part -> String? in
            if case let .reasoningDelta(_, delta, _) = part { return delta }
            return nil
        }.joined()
        #expect(reasoning.hasPrefix("First, the user is asking about the weather"))

        let toolCalls = parts.compactMap { part -> LanguageModelV4ToolCall? in
            if case let .toolCall(toolCall) = part { return toolCall }
            return nil
        }
        #expect(toolCalls.count == 1)
        #expect(toolCalls.first?.toolCallId == "call_79382389")
        #expect(toolCalls.first?.toolName == "weather")
        #expect(toolCalls.first?.input == #"{"location":"San Francisco"}"#)

        guard case let .finish(finishReason, usage, _) = parts.last else {
            Issue.record("Expected fixture stream finish")
            return
        }
        #expect(finishReason == .init(unified: .toolCalls, raw: "tool_calls"))
        #expect(usage.inputTokens.total == 307)
        #expect(usage.inputTokens.noCache == 1)
        #expect(usage.inputTokens.cacheRead == 306)
        #expect(usage.outputTokens.total == 26)
        #expect(usage.outputTokens.reasoning == 227)
        #expect(usage.outputTokens.text == -201)
    }
}
