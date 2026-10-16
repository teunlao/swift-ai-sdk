import Foundation
import Testing
import AISDKProvider
import GoogleProvider

@Suite("Google response and option contracts")
struct GoogleResponseTests {
    @Test("code execution, signed files and grounding sources remain distinct content")
    func contentAndSources() async throws {
        let transport = GoogleTransport([.init(try googleFixture("content.json"))])
        let model = await transport.provider().chat(modelId: "gemini-3.8-flash")
        let result = try await model.doGenerate(options: .init(prompt: googlePrompt, tools: [.provider(.init(id: "google.code_execution", name: "python", args: [:]))]))
        #expect(result.finishReason.unified == .stop)
        let call = try #require(result.content.compactMap { if case .toolCall(let value) = $0 { return value }; return nil }.first)
        #expect(call.toolName == "python")
        #expect(call.providerExecuted == true)
        let tool = try #require(result.content.compactMap { if case .toolResult(let value) = $0 { return value }; return nil }.first)
        #expect(tool.result == .object(["outcome": .string("OUTCOME_OK"), "output": .string("")]))
        let file = try #require(result.content.compactMap { if case .file(let value) = $0 { return value }; return nil }.first)
        #expect(file.mediaType == "audio/wav")
        #expect(file.providerMetadata?["google"]?["thoughtSignature"] == .string("file-signature"))
        let sources = result.content.compactMap { if case .source(let value) = $0 { return value }; return nil }
        #expect(sources.count == 4)
        guard case .document(_, let type, let title, let filename, _) = sources[0] else { Issue.record("missing document source"); return }
        #expect(type == "application/pdf" && title == "Report" && filename == "report.pdf")
        #expect(object(array(result.providerMetadata?["google"]?["safetyRatings"]).first) == ["category": .string("SAFE"), "probabilityScore": .number(0.5)])
    }

    @Test("explicit empty provider options and unstructured JSON output preserve request semantics")
    func explicitOptions() async throws {
        let transport = GoogleTransport([.init(try googleFixture("text.json"))])
        let model = await transport.provider().chat(modelId: "gemini-2.5-flash")
        let options = GoogleLanguageModelOptions(thinkingConfig: .init(), structuredOutputs: false, safetySettings: [], labels: [:], imageConfig: .init(), retrievalConfig: .init())
        let result = try await model.doGenerate(options: .init(prompt: googlePrompt, frequencyPenalty: 1, responseFormat: .json(schema: .object(["const": .number(1)]), name: nil, description: nil), providerOptions: ["google": options.toDictionary()]))
        #expect(result.warnings == [.unsupported(feature: "frequencyPenalty", details: nil)])
        let request = try #require(await transport.captured().first)
        let body = try googleBody(request)
        let generation = object(body["generationConfig"])
        #expect(generation["responseMimeType"] == .string("application/json"))
        #expect(generation["responseJsonSchema"] == nil)
        #expect(generation["thinkingConfig"] == .object([:]))
        #expect(generation["imageConfig"] == .object([:]))
        #expect(body["safetySettings"] == .array([]))
        #expect(body["labels"] == .object([:]))
    }

    @Test("invalid declared provider options fail before an HTTP request", arguments: [
        ["responseModalities": JSONValue.null],
        ["thinkingConfig": .object(["includeThoughts": .null])],
        ["serviceTier": .string("invalid-tier")]
    ])
    func invalidOptions(_ options: JSONObject) async throws {
        let transport = GoogleTransport([])
        let model = await transport.provider().chat(modelId: "gemini-3.8-flash")
        await #expect(throws: InvalidArgumentError.self) { try await model.doGenerate(options: .init(prompt: googlePrompt, providerOptions: ["google": options])) }
    }
}
