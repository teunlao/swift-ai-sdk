import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import OpenAIProvider

private let completionPrompt: LanguageModelV4Prompt = [
    .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
]
private let completionResponse = #"{"id":"cmpl-test","created":0,"model":"instruct","choices":[{"text":"Hello!","finish_reason":"stop","logprobs":{"tokens":["Hello!"],"token_logprobs":[-0.5],"top_logprobs":null,"ignored":true}}],"usage":{"prompt_tokens":4,"completion_tokens":2,"total_tokens":6,"ignored":true}}"#
private let completionUsage: JSONValue = .object(["prompt_tokens": .number(4), "completion_tokens": .number(2), "total_tokens": .number(6), "ignored": .bool(true)])
private let completionLogprobs: JSONValue = .object(["tokens": .array([.string("Hello!")]), "token_logprobs": .array([.number(-0.5)]), "top_logprobs": .null])

@Suite("OpenAI Completion contracts")
struct OpenAICompletionLanguageModelTests {
    private func model(
        body: String = completionResponse,
        streaming: Bool = false,
        provider: String = "openai.completion",
        status: Int = 200,
        inspect: @escaping @Sendable (URLRequest) throws -> Void = { _ in }
    ) -> OpenAICompletionLanguageModel {
        OpenAICompletionLanguageModel(modelId: "instruct", config: .init(
            provider: provider,
            url: { "https://example.com\($0.path)" },
            headers: { ["Authorization": "Bearer test", "X-Override": "provider"] },
            fetch: { request in
                try inspect(request)
                return FetchResponse(body: .data(Data(body.utf8)), urlResponse: HTTPURLResponse(
                    url: request.url!, statusCode: status, httpVersion: nil,
                    headerFields: ["Content-Type": streaming ? "text/event-stream" : "application/json", "X-Response": "value"]
                )!)
            }
        ))
    }

    private func events(_ frames: [String]) -> String {
        (frames + ["[DONE]"]).map { "data: \($0)\n\n" }.joined()
    }

    @Test("generate maps the wire response, usage and metadata without dropping explicit null")
    func generateResponse() async throws {
        let result = try await model().doGenerate(options: .init(prompt: completionPrompt))
        #expect(result.content == [.text(.init(text: "Hello!"))])
        #expect(result.finishReason == .init(unified: .stop, raw: "stop"))
        #expect(result.usage.inputTokens.total == 4)
        #expect(result.usage.inputTokens.noCache == 4)
        #expect(result.usage.outputTokens.total == 2)
        #expect(result.usage.outputTokens.text == 2)
        #expect(result.usage.raw == completionUsage)
        #expect(result.providerMetadata == ["openai": ["logprobs": completionLogprobs]])
        #expect(result.response?.id == "cmpl-test")
        #expect(result.response?.modelId == "instruct")
        #expect(result.response?.timestamp == Date(timeIntervalSince1970: 0))
        #expect(result.response?.headers?["x-response"] == "value")
        let responseBody = try #require(result.response?.body)
        let rawResponse = try jsonValue(from: responseBody)
        let expectedResponse = try JSONDecoder().decode(JSONValue.self, from: Data(completionResponse.utf8))
        #expect(rawResponse == expectedResponse)
    }

    @Test("provider completion sends role projection, settings, headers and ordered stops")
    func generateRequest() async throws {
        let expected: JSONValue = .object([
            "model": .string("instruct"), "prompt": .string("System\n\nuser:\nHello\n\nassistant:\nPrior\n\nassistant:\n"),
            "stop": .array([.string("\nuser:"), .string("END")]),
            "echo": .bool(false), "logit_bias": .object(["token": .number(-4)]), "logprobs": .number(1),
            "suffix": .string(""), "user": .string("base-user"), "max_tokens": .number(12),
            "temperature": .number(0.5), "top_p": .number(0.8), "frequency_penalty": .number(0.2),
            "presence_penalty": .number(0.3), "seed": .number(7)
        ])
        let provider = try createOpenAI(settings: .init(apiKey: "test", headers: ["X-Override": "provider"], name: "custom", fetch: { request in
            #expect(request.url?.absoluteString == "https://api.openai.com/v1/completions")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test")
            #expect(request.value(forHTTPHeaderField: "X-Override") == "request")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
            let body = try #require(request.httpBody)
            let decoded = try JSONDecoder().decode(JSONValue.self, from: body)
            #expect(decoded == expected)
            return FetchResponse(body: .data(Data(completionResponse.utf8)), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
        }))
        let prompt: LanguageModelV4Prompt = [
            .system(content: "System", providerOptions: nil),
            .user(content: [.text(.init(text: "Hello")), .file(.init(data: .text("file"), mediaType: "text/plain"))], providerOptions: nil),
            .assistant(content: [.reasoning(.init(text: "internal")), .text(.init(text: "Prior")), .custom(.init(kind: "custom"))], providerOptions: nil)
        ]
        let result = try await provider.completion("instruct").doGenerate(options: .init(
            prompt: prompt, maxOutputTokens: 12, temperature: 0.5, stopSequences: ["END"], topP: 0.8, topK: 3,
            presencePenalty: 0.3, frequencyPenalty: 0.2, responseFormat: .json(schema: nil, name: nil, description: nil), seed: 7,
            tools: [.function(.init(name: "tool", inputSchema: .object([:])))], toolChoice: .auto,
            headers: ["X-Override": "request"], reasoning: .high,
            providerOptions: [
                "openai": ["echo": .bool(true), "logitBias": .object(["token": .number(-4)]), "suffix": .string("base"), "user": .string("base-user"), "logprobs": .bool(true)],
                "custom": ["echo": .bool(false), "suffix": .string(""), "logprobs": .number(1)]
            ]
        ))
        let requestBody = try #require(result.request?.body)
        let rawRequest = try jsonValue(from: requestBody)
        #expect(rawRequest == expected)
        #expect(result.warnings == [
            .unsupported(feature: "topK", details: nil), .unsupported(feature: "tools", details: nil),
            .unsupported(feature: "toolChoice", details: nil),
            .unsupported(feature: "responseFormat", details: "JSON response format is not supported.")
        ])
    }

    @Test("logprobs boolean settings map to the completion API", arguments: [true, false])
    func logprobs(_ enabled: Bool) async throws {
        let model = model(inspect: { request in
            let body = try JSONDecoder().decode([String: JSONValue].self, from: #require(request.httpBody))
            #expect(body["logprobs"] == (enabled ? JSONValue.number(0) : Optional<JSONValue>.none))
        })
        let result = try await model.doGenerate(options: .init(prompt: completionPrompt, providerOptions: ["openai": ["logprobs": .bool(enabled)]]))
        #expect(result.content == [.text(.init(text: "Hello!"))])
    }

    @Test("a provider prefix is trimmed without replacing an empty namespace", arguments: [" custom .completion", ".completion"])
    func optionNamespace(_ provider: String) async throws {
        let namespace = provider.components(separatedBy: ".")[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let model = model(provider: provider, inspect: { request in
            let body = try JSONDecoder().decode([String: JSONValue].self, from: #require(request.httpBody))
            #expect(body["user"] == .string("override"))
        })
        let result = try await model.doGenerate(options: .init(prompt: completionPrompt, providerOptions: ["openai": ["user": .string("base")], namespace: ["user": .string("override")]]))
        #expect(result.content == [.text(.init(text: "Hello!"))])
    }

    @Test("completion options reject null and non-finite numbers at the public boundary", arguments: [
        ["logprobs": JSONValue.null], ["logprobs": JSONValue.number(.infinity)], ["logitBias": .object(["token": JSONValue.number(.infinity)])]
    ])
    func invalidOptions(_ options: [String: JSONValue]) async throws {
        await #expect(throws: InvalidArgumentError.self) {
            _ = try await model().doGenerate(options: .init(prompt: completionPrompt, providerOptions: ["openai": options]))
        }
    }

    @Test("late system and tool messages fail as typed prompt errors")
    func invalidPrompt() async throws {
        await #expect(throws: InvalidPromptError.self) {
            _ = try await model().doGenerate(options: .init(prompt: completionPrompt + [.system(content: "late", providerOptions: nil)]))
        }
        await #expect(throws: UnsupportedFunctionalityError.self) {
            _ = try await model().doGenerate(options: .init(prompt: [.tool(content: [], providerOptions: nil)]))
        }
        await #expect(throws: UnsupportedFunctionalityError.self) {
            _ = try await model().doGenerate(options: .init(prompt: [.assistant(content: [.toolCall(.init(toolCallId: "id", toolName: "tool", input: .object([:])))], providerOptions: nil)]))
        }
    }

    @Test("finish reasons preserve provider values and map unified results", arguments: ["length", "content_filter", "tool_calls", "eos"])
    func finishReason(_ reason: String) async throws {
        let expected: [String: LanguageModelV4FinishReason.Unified] = ["length": .length, "content_filter": .contentFilter, "tool_calls": .toolCalls, "eos": .other]
        let result = try await model(body: "{\"choices\":[{\"text\":\"\",\"finish_reason\":\"\(reason)\"}]}").doGenerate(options: .init(prompt: completionPrompt))
        #expect(result.finishReason == .init(unified: try #require(expected[reason]), raw: reason))
        #expect(result.usage == .init())
        #expect(result.providerMetadata == ["openai": [:]])
    }

    @Test("incomplete API responses are rejected instead of returning partial results", arguments: [
        #"{"choices":[{"text":"x"}]}"#,
        #"{"choices":[{"text":null,"finish_reason":"stop"}]}"#,
        #"{"choices":[{"text":"x","finish_reason":"stop"}],"usage":{"prompt_tokens":1}}"#
    ])
    func responseValidation(_ body: String) async throws {
        await #expect(throws: APICallError.self) {
            _ = try await model(body: body).doGenerate(options: .init(prompt: completionPrompt))
        }
    }

    @Test("empty choices and HTTP failures retain typed failure contracts")
    func failures() async throws {
        await #expect(throws: InvalidResponseDataError.self) {
            _ = try await model(body: #"{"choices":[]}"#).doGenerate(options: .init(prompt: completionPrompt))
        }
        do {
            _ = try await model(body: #"{"error":{"message":"denied","type":"invalid_request_error"}}"#, status: 401).doGenerate(options: .init(prompt: completionPrompt))
            Issue.record("Expected API failure")
        } catch let error as APICallError {
            #expect(error.message == "denied")
            #expect(error.statusCode == 401)
            #expect(!error.isRetryable)
        }
    }

    @Test("stream preserves raw order, uses the data-first union and consumes final usage")
    func streamResponse() async throws {
        let first = #"{"id":"first","created":0,"model":"instruct","choices":[{"index":0,"text":"Hello","finish_reason":null}],"error":{"message":"ignore","type":"server_error"}}"#
        let last = #"{"id":"last","choices":[{"index":0,"text":"!","finish_reason":"stop","logprobs":{"tokens":["Hello!"],"token_logprobs":[-0.5],"top_logprobs":null}}]}"#
        let usage = #"{"choices":[],"usage":{"prompt_tokens":4,"completion_tokens":2,"total_tokens":6,"ignored":true}}"#
        let model = model(body: events([first, last, usage]), streaming: true, inspect: { request in
            let body = try JSONDecoder().decode([String: JSONValue].self, from: #require(request.httpBody))
            #expect(request.url?.path == "/completions")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test")
            #expect(request.value(forHTTPHeaderField: "X-Override") == "request")
            #expect(body["model"] == .string("instruct"))
            #expect(body["prompt"] == .string("user:\nHello\n\nassistant:\n"))
            #expect(body["stream"] == .bool(true))
            #expect(body["stream_options"] == .object(["include_usage": .bool(true)]))
        })
        let result = try await model.doStream(options: .init(prompt: completionPrompt, includeRawChunks: true, headers: ["X-Override": "request"]))
        var parts: [LanguageModelV4StreamPart] = []
        for try await part in result.stream { parts.append(part) }
        #expect(result.response?.headers?["x-response"] == "value")
        #expect(parts == [
            .streamStart(warnings: []),
            .raw(rawValue: try JSONDecoder().decode(JSONValue.self, from: Data(first.utf8))),
            .responseMetadata(id: "first", modelId: "instruct", timestamp: Date(timeIntervalSince1970: 0)),
            .textStart(id: "0", providerMetadata: nil), .textDelta(id: "0", delta: "Hello", providerMetadata: nil),
            .raw(rawValue: try JSONDecoder().decode(JSONValue.self, from: Data(last.utf8))),
            .textDelta(id: "0", delta: "!", providerMetadata: nil),
            .raw(rawValue: try JSONDecoder().decode(JSONValue.self, from: Data(usage.utf8))),
            .textEnd(id: "0", providerMetadata: nil),
            .finish(finishReason: .init(unified: .stop, raw: "stop"), usage: .init(inputTokens: .init(total: 4, noCache: 4), outputTokens: .init(total: 2, text: 2), raw: completionUsage), providerMetadata: ["openai": ["logprobs": completionLogprobs]])
        ])
    }

    @Test("metadata and finish-only chunks cannot hide a pre-output error", arguments: [false, true])
    func preOutputError(_ metadataFirst: Bool) async throws {
        var frames = [String]()
        if metadataFirst { frames.append(#"{"id":"accepted","choices":[{"index":0,"text":"","finish_reason":"stop"}]}"#) }
        frames.append(#"{"error":{"message":"quota exhausted","type":"insufficient_quota","code":"insufficient_quota","param":null}}"#)
        do {
            _ = try await model(body: events(frames), streaming: true).doStream(options: .init(prompt: completionPrompt))
            Issue.record("Expected pre-output API failure")
        } catch let error as APICallError {
            #expect(error.message == "quota exhausted")
            #expect(error.statusCode == 429)
            #expect(!error.isRetryable)
            #expect(error.url == "https://example.com/completions")
        }
    }

    @Test("midstream errors preserve explicit null and distinguish untyped frames", arguments: [false, true])
    func midstreamError(_ explicitNull: Bool) async throws {
        let frame = explicitNull ? #"{"message":"stopped","param":null}"# : #"{"message":"stopped"}"#
        let result = try await model(body: events([
            #"{"choices":[{"index":0,"text":"hello"}]}"#, "{\"error\":\(frame)}"
        ]), streaming: true).doStream(options: .init(prompt: completionPrompt))
        var parts: [LanguageModelV4StreamPart] = []
        for try await part in result.stream { parts.append(part) }
        let expected = try JSONDecoder().decode(JSONValue.self, from: Data(frame.utf8))
        #expect(parts.contains(.textDelta(id: "0", delta: "hello", providerMetadata: nil)))
        let error = try #require(parts.compactMap { part -> LanguageModelV4StreamError? in
            if case .error(let error) = part { return error }; return nil
        }.first)
        if explicitNull {
            guard case .providerStreamError(let typed) = error else { Issue.record("Expected typed provider failure"); return }
            #expect(typed.data == expected)
            #expect(typed.message == "stopped")
            #expect(typed.statusCode == 500)
            #expect(typed.isRetryable == true)
        } else {
            guard case .value(let value) = error else { Issue.record("Expected original untyped error"); return }
            #expect(value == expected)
        }
        #expect(parts.suffix(2).first == .textEnd(id: "0", providerMetadata: nil))
        #expect(parts.last == .finish(finishReason: .init(unified: .error), usage: .init(), providerMetadata: ["openai": [:]]))
    }

    @Test("malformed chunks emit parse errors followed by an error finish", arguments: [
        "{unparsable}", #"{"choices":[{"index":0}]}"#
    ])
    func streamValidation(_ frame: String) async throws {
        let result = try await model(body: events([frame]), streaming: true).doStream(options: .init(prompt: completionPrompt))
        var parts: [LanguageModelV4StreamPart] = []
        for try await part in result.stream { parts.append(part) }
        #expect(parts.count == 3)
        guard case .error(.error(let error)) = parts.dropFirst().first else { Issue.record("Expected thrown parse/validation error"); return }
        #expect(JSONParseError.isInstance(error) || TypeValidationError.isInstance(error))
        #expect(parts.last == .finish(finishReason: .init(unified: .error), usage: .init(), providerMetadata: ["openai": [:]]))
    }

    @Test("empty streams finish without opening a text segment")
    func emptyStream() async throws {
        let result = try await model(body: events([]), streaming: true).doStream(options: .init(prompt: completionPrompt))
        var parts: [LanguageModelV4StreamPart] = []
        for try await part in result.stream { parts.append(part) }
        #expect(parts == [.streamStart(warnings: []), .finish(finishReason: .init(unified: .other), usage: .init(), providerMetadata: ["openai": [:]])])
    }

    @Test("canceling the consumer closes the Completion response body", .timeLimit(.minutes(1)))
    func cancelConsumer() async throws {
        let (body, continuation) = AsyncThrowingStream<Data, Error>.makeStream()
        let (closed, closeContinuation) = AsyncStream<Void>.makeStream()
        let (output, outputContinuation) = AsyncStream<Void>.makeStream()
        continuation.onTermination = { _ in closeContinuation.yield(()); closeContinuation.finish() }
        continuation.yield(Data("data: {\"choices\":[{\"index\":0,\"text\":\"hello\"}]}\n\n".utf8))
        let model = OpenAICompletionLanguageModel(modelId: "instruct", config: .init(provider: "openai.completion", url: { _ in "https://example.com/completions" }, fetch: { request in
            FetchResponse(body: .stream(body), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!)
        }))
        let consumer = Task {
            let result = try await model.doStream(options: .init(prompt: completionPrompt))
            for try await part in result.stream {
                if case .textDelta(_, "hello", _) = part { outputContinuation.yield(()); outputContinuation.finish() }
            }
        }
        var outputIterator = output.makeAsyncIterator()
        #expect(await outputIterator.next() != nil)
        consumer.cancel()
        _ = try? await consumer.value
        var closedIterator = closed.makeAsyncIterator()
        #expect(await closedIterator.next() != nil)
    }
}
