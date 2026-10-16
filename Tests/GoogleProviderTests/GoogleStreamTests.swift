import Foundation
import Testing
import AISDKProvider
import GoogleProvider

@Suite("Google streaming V4")
struct GoogleLanguageModelParityTests {
    @Test("stream preserves source, block, server-tool and client-tool ordering")
    func streamOrder() async throws {
        let transport = GoogleTransport([.init(try googleFixture("stream.sse"), headers: ["Content-Type": "text/event-stream"])])
        let model = await transport.provider().chat(modelId: "gemini-3.8-flash")
        let result = try await model.doStream(options: .init(prompt: googlePrompt))
        let parts = try await googleCollect(result.stream)
        #expect(parts.map(kind) == ["start", "metadata", "source", "reasoning-start", "reasoning-delta", "reasoning-end", "text-start", "text-delta", "text-end", "reasoning-file", "call:server:google_search", "result:server:google_search", "input-start", "input-end", "call:lookup", "finish"])
        let calls = parts.compactMap { if case .toolCall(let call) = $0 { return call }; return nil }
        #expect(calls.map(\.toolCallId) == ["server-id", "client-id"])
        #expect(calls.last?.input == "{}")
        let files = parts.compactMap { if case .reasoningFile(let file) = $0 { return file }; return nil }
        #expect(files.first?.providerMetadata?["google"]?["thoughtSignature"] == .string("file-signature"))
        guard case .finish(let reason, let usage, let metadata) = parts.last else { Issue.record("missing finish"); return }
        #expect(reason.unified == .toolCalls)
        #expect(usage.inputTokens.total == 7)
        #expect(object(usage.raw)["custom"] == .number(42))
        #expect(metadata?["google"]?["serviceTier"] == .string("flex"))
    }

    @Test("partial nested function arguments concatenate into valid final JSON")
    func partialArguments() async throws {
        let transport = GoogleTransport([.init(try googleFixture("partial.sse"), headers: ["Content-Type": "text/event-stream"])])
        let model = await transport.provider().chat(modelId: "gemini-3.8-flash")
        let parts = try await googleCollect(model.doStream(options: .init(prompt: googlePrompt)).stream)
        let deltas = parts.compactMap { if case .toolInputDelta(_, let delta, _) = $0 { return delta }; return nil }.joined()
        let call = try #require(parts.compactMap { if case .toolCall(let call) = $0 { return call }; return nil }.first)
        let expected: JSONValue = .object(["recipe": .object(["name": .string("Lasagna")]), "ingredients": .array([.string("noodles")])])
        #expect(try JSONDecoder().decode(JSONValue.self, from: Data(deltas.utf8)) == expected)
        #expect(try JSONDecoder().decode(JSONValue.self, from: Data(call.input.utf8)) == expected)
        #expect(call.toolCallId == "partial-id")
    }

    @Test("stream follows continuation hops without splitting text blocks")
    func streamContinuation() async throws {
        func sse(_ filename: String) throws -> Data {
            Data("data: \(String(decoding: try googleFixture(filename), as: UTF8.self))\n\n".utf8)
        }
        let transport = GoogleTransport([.init(try sse("continuation-first.json"), headers: ["Content-Type": "text/event-stream"]), .init(try sse("continuation-last.json"), headers: ["Content-Type": "text/event-stream"])])
        let model = await transport.provider().chat(modelId: "gemini-4-argon")
        let result = try await model.doStream(options: .init(prompt: googlePrompt))
        let parts = try await googleCollect(result.stream)
        #expect(parts.filter { if case .textStart = $0 { return true }; return false }.count == 1)
        #expect(parts.compactMap { if case .textDelta(_, let delta, _) = $0 { return delta }; return nil }.joined() == "firstlast")
        guard case .finish(let reason, let usage, let metadata) = parts.last else { Issue.record("missing finish"); return }
        #expect(reason.unified == .stop)
        #expect(usage.inputTokens.total == 25)
        #expect(metadata?["google"]?["initialPromptTokenCount"] == .number(10))
    }

    private func kind(_ part: LanguageModelV4StreamPart) -> String {
        switch part {
        case .streamStart: return "start"
        case .responseMetadata: return "metadata"
        case .source: return "source"
        case .reasoningStart: return "reasoning-start"
        case .reasoningDelta: return "reasoning-delta"
        case .reasoningEnd: return "reasoning-end"
        case .textStart: return "text-start"
        case .textDelta: return "text-delta"
        case .textEnd: return "text-end"
        case .reasoningFile: return "reasoning-file"
        case .toolCall(let call): return "call:\(call.toolName)"
        case .toolResult(let result): return "result:\(result.toolName)"
        case .toolInputStart: return "input-start"
        case .toolInputDelta: return "input-delta"
        case .toolInputEnd: return "input-end"
        case .finish: return "finish"
        default: return "other"
        }
    }
}
