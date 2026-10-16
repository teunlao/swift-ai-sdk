import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import GoogleProvider

@Suite("Google language V4")
struct GoogleLanguageModelTests {
    @Test("structured requests preserve JSON schema and map reasoning and usage")
    func structuredRequest() async throws {
        let transport = GoogleTransport([.init(try googleFixture("text.json"))])
        let provider = await transport.provider()
        let schema: JSONValue = .object(["type": .string("object"), "additionalProperties": .bool(false), "properties": .object(["status": .object(["const": .string("ok")])]), "$defs": .object(["item": .object(["const": .number(1)])])])
        let result = try await provider.chat(modelId: "gemini-3.8-flash").doGenerate(options: .init(prompt: googlePrompt, responseFormat: .json(schema: schema, name: nil, description: nil), headers: ["X-Request": "call"], reasoning: LanguageModelV4ReasoningEffort.none, providerOptions: ["google": ["serviceTier": .string("priority"), "threshold": .string("BLOCK_NONE"), "imageConfig": .object(["imageSize": .string("512"), "aspectRatio": .string("8:1")])]]))
        #expect(result.content == [.text(.init(text: "Hello", providerMetadata: ["google": ["thoughtSignature": .string("signature")]]))])
        #expect(result.usage.inputTokens.total == 11)
        #expect(result.usage.inputTokens.noCache == 7)
        #expect(result.usage.outputTokens.total == 5)
        #expect(object(result.usage.raw)["customMeter"] == .number(7))
        #expect(result.providerMetadata?["google"]?["serviceTier"] == .string("priority"))
        let request = try #require(await transport.captured().first)
        let body = try googleBody(request)
        let generation = object(body["generationConfig"])
        #expect(generation["responseMimeType"] == .string("application/json"))
        #expect(object(generation["responseJsonSchema"])["additionalProperties"] == .bool(false))
        #expect(object(object(object(generation["responseJsonSchema"])["properties"])["status"])["enum"] == .array([.string("ok")]))
        #expect(object(generation["thinkingConfig"])["thinkingLevel"] == .string("low"))
        #expect(array(body["safetySettings"]).count == 4)
        #expect(request.value(forHTTPHeaderField: "X-Request") == "call")
        #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "test-key")
        #expect(request.value(forHTTPHeaderField: "User-Agent")?.contains("ai-sdk-google/") == true)
    }

    @Test("blocked prompts map to content filtering without a candidate")
    func promptBlocked() async throws {
        let transport = GoogleTransport([.init(try googleFixture("blocked.json"))])
        let model = await transport.provider().chat(modelId: "gemini-3.8-flash")
        let result = try await model.doGenerate(options: .init(prompt: googlePrompt))
        #expect(result.finishReason == .init(unified: .contentFilter, raw: "SAFETY"))
        #expect(result.content.isEmpty)
        #expect(object(result.providerMetadata?["google"]?["promptFeedback"])["blockReason"] == .string("SAFETY"))
    }

    @Test("continuations replay the original request and sum usage")
    func continuation() async throws {
        let transport = GoogleTransport([.init(try googleFixture("continuation-first.json")), .init(try googleFixture("continuation-last.json"))])
        let model = await transport.provider().chat(modelId: "gemini-4-argon")
        let result = try await model.doGenerate(options: .init(prompt: googlePrompt, maxOutputTokens: 100000))
        #expect(result.content.compactMap { if case .text(let text) = $0 { return text.text }; return nil } == ["first", "last"])
        #expect(result.usage.inputTokens.total == 25)
        #expect(result.usage.outputTokens.total == 3)
        #expect(result.providerMetadata?["google"]?["initialPromptTokenCount"] == .number(10))
        let requests = await transport.captured()
        let second = try googleBody(#require(requests.last))
        #expect(second["continuationToken"] == .string("continue-here"))
        #expect(second["contents"] == (try googleBody(#require(requests.first)))["contents"])
        #expect(array(object(result.usage.raw)["promptTokensDetails"]) == [.object(["modality": .string("TEXT"), "tokenCount": .number(22)])])
    }

    @Test("older Gemini models implement JSON output as a response tool")
    func jsonResponseTool() async throws {
        let response: JSONValue = .object(["candidates": .array([.object(["content": .object(["parts": .array([.object(["text": .string("ignored")]), .object(["functionCall": .object(["name": .string("json_1"), "args": .object(["answer": .number(7)])])])])]), "finishReason": .string("STOP")])])])
        let transport = GoogleTransport([.init(try googleData(response))])
        let model = await transport.provider().chat(modelId: "gemini-2.5-flash")
        let result = try await model.doGenerate(options: .init(prompt: googlePrompt, responseFormat: .json(schema: .object(["type": .string("object")]), name: nil, description: nil), tools: [.function(.init(name: "json", inputSchema: .object(["type": .string("object")])))]))
        let text = try #require(result.content.compactMap { if case .text(let text) = $0 { return text.text }; return nil }.first)
        #expect(try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)) == .object(["answer": .number(7)]))
        #expect(result.finishReason.unified == .stop)
        let request = try #require(await transport.captured().first)
        let body = try googleBody(request)
        let declarations = array(object(array(body["tools"]).first)["functionDeclarations"])
        #expect(object(declarations.last)["name"] == .string("json_1"))
        #expect(object(body["generationConfig"])["responseMimeType"] == nil)
    }
}
