import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import CohereProvider

@Suite("CohereChatLanguageModel")
struct CohereChatLanguageModelTests {
    private let testPrompt: LanguageModelV3Prompt = [
        .system(content: "you are a friendly bot!", providerOptions: nil),
        .user(content: [.text(.init(text: "Hello"))], providerOptions: nil),
    ]

    private func makeModel(
        generateId: @escaping @Sendable () -> String = { UUID().uuidString },
        headers: [String: String]? = nil
    ) -> (CohereChatLanguageModel, RequestRecorder, ResponseBox) {
        let recorder = RequestRecorder()
        let placeholderResponse = FetchResponse(
            body: .data(Data()),
            urlResponse: HTTPURLResponse(
                url: HTTPTestHelpers.chatURL,
                statusCode: 500,
                httpVersion: "HTTP/1.1",
                headerFields: [:]
            )!
        )
        let responseBox = ResponseBox(initial: placeholderResponse)

        let fetch: FetchFunction = { request in
            await recorder.record(request)
            return await responseBox.value()
        }

        let provider = createCohere(settings: .init(
            apiKey: "test-api-key",
            headers: headers,
            fetch: fetch,
            generateId: generateId
        ))

        return (provider.chat(modelId: .commandRPlus), recorder, responseBox)
    }

    private func fixturesDirectory() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("external/vercel-ai-sdk/packages/cohere/src/__fixtures__")
    }

    private func loadJSONFixture(_ name: String) throws -> Any {
        let url = fixturesDirectory().appendingPathComponent("\(name).json")
        let data = try Data(contentsOf: url)
        return try JSONSerialization.jsonObject(with: data)
    }

    private func loadChunksFixture(_ name: String) throws -> [String] {
        let url = fixturesDirectory().appendingPathComponent("\(name).chunks.txt")
        let text = try String(contentsOf: url, encoding: .utf8)
        return text
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { line in
                let data = Data(line.utf8)
                let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                let type = object?["type"] as? String ?? "message"
                return "event: \(type)\ndata: \(line)\n\n"
            }
    }

    private func collectTextDeltas(_ parts: [LanguageModelV3StreamPart]) -> String {
        parts.compactMap { part in
            if case .textDelta(_, let delta, _) = part { return delta }
            return nil
        }.joined()
    }

    private func collectReasoningDeltas(_ parts: [LanguageModelV3StreamPart]) -> String {
        parts.compactMap { part in
            if case .reasoningDelta(_, let delta, _) = part { return delta }
            return nil
        }.joined()
    }

    // MARK: - doGenerate

    @Test("doGenerate extracts text response")
    func doGenerateExtractsText() async throws {
        let (model, _, responseBox) = makeModel()
        await responseBox.setJSON(url: HTTPTestHelpers.chatURL, body: try loadJSONFixture("cohere-text"))

        let result = try await model.doGenerate(options: .init(prompt: testPrompt))

        #expect(result.content == [
            .text(.init(text: "The capital of France is Paris.")),
        ])
        #expect(result.finishReason.unified == .stop)
        #expect(result.finishReason.raw == "COMPLETE")
    }

    @Test("doGenerate maps MAX_TOKENS finish reason to length")
    func doGenerateMaxTokensFinishReason() async throws {
        let (model, _, responseBox) = makeModel()
        await responseBox.setJSON(url: HTTPTestHelpers.chatURL, body: try loadJSONFixture("cohere-max-tokens"))

        let result = try await model.doGenerate(options: .init(prompt: testPrompt))
        #expect(result.finishReason.unified == .length)
        #expect(result.finishReason.raw == "MAX_TOKENS")
    }

    @Test("doGenerate extracts tool calls")
    func doGenerateExtractsToolCalls() async throws {
        let (model, _, responseBox) = makeModel()
        await responseBox.setJSON(url: HTTPTestHelpers.chatURL, body: try loadJSONFixture("cohere-tool-call"))

        let tool = LanguageModelV3Tool.function(.init(
            name: "test-tool",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object(["value": .object(["type": .string("string")])]),
                "required": .array([.string("value")]),
                "additionalProperties": .bool(false),
                "$schema": .string("http://json-schema.org/draft-07/schema#"),
            ])
        ))

        let result = try await model.doGenerate(options: .init(prompt: testPrompt, tools: [tool]))

        let toolCalls = result.content.compactMap { content -> LanguageModelV3ToolCall? in
            if case .toolCall(let call) = content { return call }
            return nil
        }
        #expect(toolCalls.count == 2)
        #expect(toolCalls.first?.toolName == "weather")
        #expect(toolCalls.last?.toolName == "cityAttractions")
    }

    @Test("doGenerate handles string \"null\" tool call arguments")
    func doGenerateNullToolArguments() async throws {
        let (model, _, responseBox) = makeModel()
        await responseBox.setJSON(url: HTTPTestHelpers.chatURL, body: try loadJSONFixture("cohere-null-args"))

        let tool = LanguageModelV3Tool.function(.init(
            name: "currentTime",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([:]),
                "required": .array([]),
                "additionalProperties": .bool(false),
                "$schema": .string("http://json-schema.org/draft-07/schema#"),
            ])
        ))

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "What is the current time?"))], providerOptions: nil),
        ]

        let result = try await model.doGenerate(options: .init(prompt: prompt, tools: [tool]))

        let call = result.content.compactMap { content -> LanguageModelV3ToolCall? in
            if case .toolCall(let call) = content { return call }
            return nil
        }.first

        #expect(call?.toolName == "currentTime")
        #expect(call?.input == "{}")
    }

    @Test("doGenerate extracts reasoning content")
    func doGenerateReasoning() async throws {
        let (model, _, responseBox) = makeModel()
        await responseBox.setJSON(url: HTTPTestHelpers.chatURL, body: try loadJSONFixture("cohere-reasoning"))

        let result = try await model.doGenerate(options: .init(prompt: testPrompt))

        #expect(result.content.contains { if case .reasoning = $0 { true } else { false } })
        #expect(result.content.contains { if case .text(let text) = $0 { text.text == "2 + 2 = 4" } else { false } })
    }

    @Test("doGenerate extracts citations as document sources")
    func doGenerateCitations() async throws {
        let (model, _, responseBox) = makeModel(generateId: { "test-citation-id" })
        await responseBox.setJSON(url: HTTPTestHelpers.chatURL, body: try loadJSONFixture("cohere-citations"))

        let prompt: LanguageModelV3Prompt = [
            .user(content: [
                .text(.init(text: "What are AI benefits?")),
                .file(.init(
                    data: .base64("AI provides automation and efficiency."),
                    mediaType: "text/plain",
                    filename: "benefits.txt"
                )),
            ], providerOptions: nil),
        ]

        let result = try await model.doGenerate(options: .init(prompt: prompt))

        let sources = result.content.compactMap { content -> LanguageModelV3Source? in
            if case .source(let source) = content { return source }
            return nil
        }

        #expect(sources.count == 3)
        for source in sources {
            guard case let .document(id, mediaType, title, filename, providerMetadata) = source else {
                Issue.record("Expected document source")
                continue
            }
            #expect(id == "test-citation-id")
            #expect(mediaType == "text/plain")
            #expect(title == "benefits.txt")
            #expect(filename == nil)
            #expect(providerMetadata?["cohere"] != nil)
        }
    }

    // MARK: - documents extraction into request

    @Test("extracts text documents and sends them to the API")
    func sendsDocumentsToAPI() async throws {
        let (model, recorder, responseBox) = makeModel()
        await responseBox.setJSON(url: HTTPTestHelpers.chatURL, body: try loadJSONFixture("cohere-text"))

        let prompt: LanguageModelV3Prompt = [
            .user(content: [
                .text(.init(text: "What does this say?")),
                .file(.init(
                    data: .base64("This is a test document."),
                    mediaType: "text/plain",
                    filename: "test.txt"
                )),
            ], providerOptions: nil),
        ]

        _ = try await model.doGenerate(options: .init(prompt: prompt))

        let request = try #require(await recorder.first())
        let body = try decodeJSONBody(request)

        let documents = body["documents"] as? [[String: Any]]
        #expect(documents?.count == 1)
        let first = documents?.first?["data"] as? [String: Any]
        #expect(first?["text"] as? String == "This is a test document.")
        #expect(first?["title"] as? String == "test.txt")
    }

    @Test("does not include documents when no files are present")
    func omitsDocumentsWhenNoFilesPresent() async throws {
        let (model, recorder, responseBox) = makeModel()
        await responseBox.setJSON(url: HTTPTestHelpers.chatURL, body: try loadJSONFixture("cohere-text"))

        _ = try await model.doGenerate(options: .init(prompt: testPrompt))

        let request = try #require(await recorder.first())
        let body = try decodeJSONBody(request)
        #expect(body["documents"] == nil)
    }

    // MARK: - request mapping

    @Test("passes model and messages")
    func requestModelAndMessages() async throws {
        let (model, recorder, responseBox) = makeModel()
        await responseBox.setJSON(url: HTTPTestHelpers.chatURL, body: try loadJSONFixture("cohere-text"))

        _ = try await model.doGenerate(options: .init(prompt: testPrompt))

        let request = try #require(await recorder.first())
        let body = try decodeJSONBody(request)
        #expect(body["model"] as? String == "command-r-plus")
        let messages = body["messages"] as? [[String: Any]]
        #expect(messages?.count == 2)
        #expect(messages?.first?["role"] as? String == "system")
        #expect(messages?.first?["content"] as? String == "you are a friendly bot!")
        #expect(messages?.last?["role"] as? String == "user")
        #expect(messages?.last?["content"] as? String == "Hello")
    }

    @Test("passes tools and tool choice")
    func requestTools() async throws {
        let (model, recorder, responseBox) = makeModel()
        await responseBox.setJSON(url: HTTPTestHelpers.chatURL, body: try loadJSONFixture("cohere-text"))

        let tool = LanguageModelV3Tool.function(.init(
            name: "test-tool",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object(["value": .object(["type": .string("string")])]),
                "required": .array([.string("value")]),
                "additionalProperties": .bool(false),
                "$schema": .string("http://json-schema.org/draft-07/schema#"),
            ])
        ))

        _ = try await model.doGenerate(options: .init(
            prompt: testPrompt,
            tools: [tool],
            toolChoice: .some(LanguageModelV3ToolChoice.none)
        ))

        let request = try #require(await recorder.first())
        let body = try decodeJSONBody(request)
        #expect(body["tool_choice"] as? String == "NONE")
        let tools = body["tools"] as? [[String: Any]]
        #expect(tools?.count == 1)
        let function = tools?.first?["function"] as? [String: Any]
        #expect(function?["name"] as? String == "test-tool")
    }

    @Test("passes response format json schema")
    func requestResponseFormat() async throws {
        let (model, recorder, responseBox) = makeModel()
        await responseBox.setJSON(url: HTTPTestHelpers.chatURL, body: try loadJSONFixture("cohere-text"))

        let schema: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([
                "text": .object(["type": .string("string")]),
            ]),
            "required": .array([.string("text")]),
        ])

        _ = try await model.doGenerate(options: .init(
            prompt: testPrompt,
            responseFormat: .json(schema: schema, name: nil, description: nil)
        ))

        let request = try #require(await recorder.first())
        let body = try decodeJSONBody(request)
        let responseFormat = body["response_format"] as? [String: Any]
        #expect(responseFormat?["type"] as? String == "json_object")
        #expect(responseFormat?["json_schema"] != nil)
    }

    @Test("merges request and provider headers")
    func requestHeaders() async throws {
        let (model, recorder, responseBox) = makeModel(headers: ["Custom-Provider-Header": "provider-header-value"])
        await responseBox.setJSON(url: HTTPTestHelpers.chatURL, body: try loadJSONFixture("cohere-text"))

        _ = try await model.doGenerate(options: .init(
            prompt: testPrompt,
            headers: ["Custom-Request-Header": "request-header-value"]
        ))

        let request = try #require(await recorder.first())
        let headers = lowercaseHeaders(request)
        #expect(headers["authorization"] == "Bearer test-api-key")
        #expect(headers["custom-provider-header"] == "provider-header-value")
        #expect(headers["custom-request-header"] == "request-header-value")
    }

    @Test("passes thinking provider option")
    func requestThinkingOption() async throws {
        let (model, recorder, responseBox) = makeModel()
        await responseBox.setJSON(url: HTTPTestHelpers.chatURL, body: try loadJSONFixture("cohere-text"))

        _ = try await model.doGenerate(options: .init(
            prompt: testPrompt,
            providerOptions: [
                "cohere": [
                    "thinking": .object([
                        "type": .string("disabled"),
                        "tokenBudget": .number(123),
                    ]),
                ],
            ]
        ))

        let request = try #require(await recorder.first())
        let body = try decodeJSONBody(request)
        let thinking = body["thinking"] as? [String: Any]
        #expect(thinking?["type"] as? String == "disabled")
        #expect((thinking?["token_budget"] as? NSNumber)?.intValue == 123)
    }

    @Test("exposes raw response headers and usage")
    func responseHeadersAndUsage() async throws {
        let (model, _, responseBox) = makeModel()
        await responseBox.setJSON(
            url: HTTPTestHelpers.chatURL,
            body: try loadJSONFixture("cohere-text"),
            headers: ["Test-Header": "test-value"]
        )

        let result = try await model.doGenerate(options: .init(prompt: testPrompt))
        #expect(result.response?.headers?["test-header"] == "test-value")
        #expect(result.usage.inputTokens.total == 507)
        #expect(result.usage.outputTokens.total == 10)
        #expect(result.response?.id == nil)
        #expect(result.response?.timestamp == nil)
        #expect(result.response?.modelId == nil)
    }

    // MARK: - doStream

    @Test("doStream streams text deltas")
    func doStreamText() async throws {
        let (model, _, responseBox) = makeModel()
        await responseBox.setStream(url: HTTPTestHelpers.chatURL, chunks: try loadChunksFixture("cohere-text"))

        let result = try await model.doStream(options: .init(prompt: testPrompt, includeRawChunks: false))
        let parts = try await collectStream(result.stream)

        #expect(collectTextDeltas(parts) == "The capital of France is Paris.")
        if let finish = parts.last, case let .finish(reason, usage, _) = finish {
            #expect(reason.unified == .stop)
            #expect(reason.raw == "COMPLETE")
            #expect(usage.outputTokens.total == 10)
        } else {
            Issue.record("Missing finish part")
        }
    }

    @Test("doStream includes raw chunks when enabled")
    func doStreamRawChunksEnabled() async throws {
        let (model, _, responseBox) = makeModel()
        await responseBox.setStream(url: HTTPTestHelpers.chatURL, chunks: try loadChunksFixture("cohere-text"))

        let result = try await model.doStream(options: .init(prompt: testPrompt, includeRawChunks: true))
        let parts = try await collectStream(result.stream)
        let rawCount = parts.filter { if case .raw = $0 { true } else { false } }.count
        #expect(rawCount > 0)
    }

    @Test("doStream does not include raw chunks when disabled")
    func doStreamRawChunksDisabled() async throws {
        let (model, _, responseBox) = makeModel()
        await responseBox.setStream(url: HTTPTestHelpers.chatURL, chunks: try loadChunksFixture("cohere-text"))

        let result = try await model.doStream(options: .init(prompt: testPrompt, includeRawChunks: false))
        let parts = try await collectStream(result.stream)
        let rawCount = parts.filter { if case .raw = $0 { true } else { false } }.count
        #expect(rawCount == 0)
    }

    @Test("doStream streams reasoning deltas")
    func doStreamReasoning() async throws {
        let (model, _, responseBox) = makeModel()
        await responseBox.setStream(url: HTTPTestHelpers.chatURL, chunks: try loadChunksFixture("cohere-reasoning"))

        let result = try await model.doStream(options: .init(prompt: testPrompt, includeRawChunks: false))
        let parts = try await collectStream(result.stream)

        #expect(collectReasoningDeltas(parts).contains("The user is asking for the sum of 2 and 2"))
        #expect(collectTextDeltas(parts) == "The answer to 2 + 2 is 4.")
    }

    @Test("doStream streams tool deltas and emits toolCall")
    func doStreamToolCall() async throws {
        let (model, _, responseBox) = makeModel()
        await responseBox.setStream(url: HTTPTestHelpers.chatURL, chunks: try loadChunksFixture("cohere-tool-call"))

        let tool = LanguageModelV3Tool.function(.init(
            name: "test-tool",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object(["value": .object(["type": .string("string")])]),
                "required": .array([.string("value")]),
                "additionalProperties": .bool(false),
                "$schema": .string("http://json-schema.org/draft-07/schema#"),
            ])
        ))

        let result = try await model.doStream(options: .init(prompt: testPrompt, tools: [tool], includeRawChunks: false))
        let parts = try await collectStream(result.stream)

        let toolCalls = parts.compactMap { part -> LanguageModelV3ToolCall? in
            if case .toolCall(let call) = part { return call }
            return nil
        }
        #expect(toolCalls.count == 2)
        #expect(toolCalls.first?.toolName == "weather")
        #expect(toolCalls.last?.toolName == "cityAttractions")
    }

    @Test("doStream handles empty tool call arguments")
    func doStreamEmptyToolCallArguments() async throws {
        let (model, _, responseBox) = makeModel()
        await responseBox.setStream(url: HTTPTestHelpers.chatURL, chunks: try loadChunksFixture("cohere-empty-tool-call"))

        let tool = LanguageModelV3Tool.function(.init(
            name: "test-tool",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([:]),
                "required": .array([]),
                "additionalProperties": .bool(false),
                "$schema": .string("http://json-schema.org/draft-07/schema#"),
            ])
        ))

        let result = try await model.doStream(options: .init(prompt: testPrompt, tools: [tool], includeRawChunks: false))
        let parts = try await collectStream(result.stream)

        let toolCall = parts.compactMap { part -> LanguageModelV3ToolCall? in
            if case .toolCall(let call) = part { return call }
            return nil
        }.first

        #expect(toolCall?.input == "{}")
    }

    // MARK: - doStream request mapping

    @Test("doStream passes stream: true in request body")
    func doStreamRequestBody() async throws {
        let (model, recorder, responseBox) = makeModel()
        await responseBox.setStream(url: HTTPTestHelpers.chatURL, chunks: try loadChunksFixture("cohere-text"))

        _ = try await model.doStream(options: .init(prompt: testPrompt, includeRawChunks: false))

        let request = try #require(await recorder.first())
        let body = try decodeJSONBody(request)
        #expect(body["stream"] as? Bool == true)
    }
}
