import Foundation
import Testing
import AISDKProvider
import GoogleProvider

@Suite("Google tool request contracts")
struct GooglePrepareToolsTests {
    @Test("new Gemini families combine built-in and strict function tools")
    func mixedTools() async throws {
        let transport = GoogleTransport([.init(try googleFixture("text.json"))])
        let model = await transport.provider().chat(modelId: "publishers/google/gemini-future")
        let schema: JSONValue = .object(["type": .string("object"), "$defs": .object(["value": .object(["type": .string("string")])]), "properties": .object(["query": .object(["$ref": .string("#/$defs/value")])]), "additionalProperties": .bool(false)])
        let tools: [LanguageModelV4Tool] = [.function(.init(name: "lookup", inputSchema: schema, strict: true)), .provider(.init(id: "google.google_search", name: "google_search", args: ["searchTypes": .object(["imageSearch": .object([:])])]))]
        let result = try await model.doGenerate(options: .init(prompt: googlePrompt, tools: tools))
        #expect(result.warnings.isEmpty)
        let request = try #require(await transport.captured().first)
        let body = try googleBody(request)
        let entries = array(body["tools"])
        #expect(object(entries.first)["googleSearch"] == .object(["searchTypes": .object(["imageSearch": .object([:])])]))
        #expect(object(array(object(entries.last)["functionDeclarations"]).first)["parametersJsonSchema"] == schema)
        #expect(object(object(body["toolConfig"])["functionCallingConfig"])["mode"] == .string("VALIDATED"))
        #expect(object(body["toolConfig"])["includeServerSideToolInvocations"] == .bool(true))
    }

    @Test("function-only strict mode requests validated calls and respects explicit tool choice")
    func strictCalls() async throws {
        let transport = GoogleTransport([.init(try googleFixture("text.json"))])
        let model = await transport.provider().chat(modelId: "gemini-2.5-flash")
        _ = try await model.doGenerate(options: .init(prompt: googlePrompt, tools: [.function(.init(name: "lookup", inputSchema: .object([:]), strict: true))], toolChoice: .tool(toolName: "lookup")))
        let request = try #require(await transport.captured().first)
        #expect(object(try googleBody(request)["toolConfig"])["functionCallingConfig"] == .object(["mode": .string("ANY"), "allowedFunctionNames": .array([.string("lookup")])]))
    }

    @Test("older model families warn when provider tools are unsupported")
    func unsupportedProviderTools() async throws {
        let transport = GoogleTransport([.init(try googleFixture("text.json"))])
        let model = await transport.provider().chat(modelId: "gemini-1.5-flash")
        let result = try await model.doGenerate(options: .init(prompt: googlePrompt, tools: [.provider(.init(id: "google.google_search", name: "google_search", args: [:]))]))
        #expect(result.warnings.count == 1)
        guard case .unsupported(let feature, _) = result.warnings[0] else { Issue.record("missing unsupported tool warning"); return }
        #expect(feature == "provider-defined tool google.google_search")
    }
}
