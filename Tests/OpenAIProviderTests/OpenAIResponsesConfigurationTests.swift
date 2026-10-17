import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import OpenAIProvider

@Suite("Responses reasoning configuration updates")
struct OpenAIResponsesConfigurationTests {
    private func model(_ id: String = "gpt-6-sol", inspect: @escaping @Sendable (JSONObject) throws -> Void = { _ in }) throws -> OpenAIResponsesLanguageModel {
        try createOpenAI(settings: .init(apiKey: "key", fetch: { request in
            try inspect(JSONDecoder().decode(JSONObject.self, from: #require(request.httpBody)))
            return FetchResponse(body: .data(Data(#"{"id":"r","created_at":1,"model":"gpt-6-sol","output":[]}"#.utf8)), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
        })).responses(id)
    }

    private func update(_ effort: String, text: String = "") -> LanguageModelV4Message {
        .system(content: text, providerOptions: ["openai": ["reasoningEffortUpdate": .string(effort)]])
    }

    @Test("updates preserve cached request effort and historical positions while changing sampling")
    func configurationHistory() async throws {
        let instance = try model { body in
            #expect(body["reasoning"] == .object(["effort": .string("high"), "summary": .string("detailed")]))
            #expect(body["temperature"] == .number(0.7))
            #expect(body["top_p"] == .number(0.8))
            #expect(body["top_logprobs"] == .number(2))
            #expect(body["input"] == .array([
                .object(["type": .string("configuration_update"), "reasoning": .object(["effort": .string("low")])]),
                .object(["role": .string("user"), "content": .array([.object(["type": .string("input_text"), "text": .string("question")])])]),
                .object(["type": .string("configuration_update"), "reasoning": .object(["effort": .string("none")])]),
                .object(["type": .string("compaction_trigger")])
            ]))
        }
        let result = try await instance.doGenerate(options: .init(
            prompt: [.user(content: [.text(.init(text: "question"))], providerOptions: nil), update("none")],
            temperature: 0.7, topP: 0.8,
            providerOptions: OpenAIOptions().responses(.init(logprobs: .number(2), reasoningEffort: "high", reasoningEffortUpdate: "low", systemMessageMode: .remove, compactionTrigger: true))))
        #expect(result.warnings.isEmpty)
    }

    @Test("an identical leading historical update is emitted once")
    func duplicateInitialUpdate() async throws {
        _ = try await model { body in
            #expect(body["input"] == .array([.object(["type": .string("configuration_update"), "reasoning": .object(["effort": .string("none")])])]))
        }.doGenerate(options: .init(prompt: [update("none")], providerOptions: ["openai": ["reasoningEffortUpdate": .string("none")]]))
    }

    @Test("unsupported historical controls fail instead of changing their meaning", arguments: ["old-model", "nonempty", "unsupported-effort", "adjacent", "pro", "compaction", "truncation"])
    func invalidHistory(_ mode: String) async throws {
        var options: JSONObject = [:]
        if mode == "pro" { options["reasoningMode"] = .string("pro") }
        if mode == "compaction" { options["contextManagement"] = .array([]) }
        if mode == "truncation" { options["truncation"] = .string("auto") }
        if mode == "adjacent" { options["reasoningEffortUpdate"] = .string("high") }
        let instance = try model(mode == "old-model" ? "gpt-5.6" : mode == "unsupported-effort" ? "gpt-6-astra" : "gpt-6-sol")
        await #expect(throws: UnsupportedFunctionalityError.self) {
            _ = try await instance.doGenerate(options: .init(prompt: [update("none", text: mode == "nonempty" ? "text" : "")], providerOptions: ["openai": options]))
        }
    }

    @Test("unsupported request updates warn and retain the original input", arguments: ["old-model", "unsupported-effort", "pro", "compaction", "truncation"])
    func unsupportedRequest(_ mode: String) async throws {
        var options: JSONObject = ["reasoningEffortUpdate": .string("none")]
        if mode == "pro" { options["reasoningMode"] = .string("pro") }
        if mode == "compaction" { options["contextManagement"] = .array([]) }
        if mode == "truncation" { options["truncation"] = .string("auto") }
        let result = try await model(mode == "old-model" ? "gpt-5.6" : mode == "unsupported-effort" ? "gpt-6-astra" : "gpt-6-sol", inspect: { body in
            #expect(body["input"] == .array([]))
        }).doGenerate(options: .init(prompt: [], providerOptions: ["openai": options]))
        #expect(result.warnings.contains { if case .unsupported(let feature, _) = $0 { feature == "reasoningEffortUpdate" } else { false } })
    }
}
