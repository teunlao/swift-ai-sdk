import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import AmazonBedrockProvider

@Suite("BedrockChatLanguageModel")
struct BedrockChatLanguageModelTests {
    @Test("Instruction JSON extraction preserves combining marks and braces across stream deltas")
    func unicodeJSON() async throws {
        let json = "{\"x\":\"\u{0301}}tail\"}"
        let response = try BedrockTestServer(json: .object([
            "output": .object(["message": .object(["role": .string("assistant"), "content": .array([.object(["text": .string("prefix " + json + " suffix")])])])]),
            "stopReason": .string("end_turn"), "usage": .object(["inputTokens": .number(1), "outputTokens": .number(1), "totalTokens": .number(2)])
        ]))
        let options = LanguageModelV4CallOptions(prompt: [], responseFormat: .json(schema: .object(["type": .string("object")]), name: nil, description: nil))
        let result = try await response.provider().chat(modelId: "anthropic.claude-sonnet-5-5").doGenerate(options: options)
        #expect(result.content == [.text(.init(text: json))])
        for deltas in [["prefix " + json + " suffix"], ["prefix {\"x\":\"", "\u{0301}}tail\"} suffix"]] {
            let frames = try deltas.map { try BedrockTestEventStream.jsonMessage(eventType: "contentBlockDelta", payload: ["contentBlockIndex": 0, "delta": ["text": $0]]) }
            let server = BedrockTestServer(data: frames.reduce(into: Data()) { $0.append($1) }, headers: ["content-type": "application/vnd.amazon.eventstream"])
            let stream = try await server.provider().chat(modelId: "anthropic.claude-sonnet-5-5").doStream(options: options)
            let parts = try await convertReadableStreamToArray(stream.stream)
            let text = parts.compactMap { part -> String? in
                if case .textDelta(_, let delta, _) = part { return delta }
                return nil
            }.joined()
            #expect(text == json)
        }
    }

    @Test("Invalid usage numbers remain raw in generated and streamed responses", arguments: [false, true])
    func unknownUsage(_ streaming: Bool) async throws {
        let raw: JSONValue = .object(["inputTokens": .number(1.5), "outputTokens": .number(1e100), "totalTokens": .number(1e100), "cacheReadInputTokens": .number(0.5), "cacheWriteInputTokens": .number(1e100)])
        let usage: LanguageModelV4Usage
        if streaming {
            let frame = try BedrockTestEventStream.jsonMessage(eventType: "metadata", payload: ["usage": ["inputTokens": 1.5, "outputTokens": 1e100, "totalTokens": 1e100, "cacheReadInputTokens": 0.5, "cacheWriteInputTokens": 1e100]])
            let server = BedrockTestServer(data: frame, headers: ["content-type": "application/vnd.amazon.eventstream"])
            let result = try await server.provider().chat(modelId: "model").doStream(options: .init(prompt: []))
            let parts = try await convertReadableStreamToArray(result.stream)
            guard case .finish(_, let value, _)? = parts.last else { Issue.record("Expected finish"); return }
            usage = value
        } else {
            let server = try BedrockTestServer(json: .object(["output": .object(["message": .object(["role": .string("assistant"), "content": .array([])])]), "stopReason": .string("end_turn"), "usage": raw]))
            usage = try await server.provider().chat(modelId: "model").doGenerate(options: .init(prompt: [])).usage
        }
        #expect(usage.inputTokens.total == nil)
        #expect(usage.inputTokens.noCache == nil)
        #expect(usage.inputTokens.cacheRead == nil)
        #expect(usage.inputTokens.cacheWrite == nil)
        #expect(usage.outputTokens.total == nil)
        #expect(usage.raw == raw)
    }

    @Test("Token budgets reject fractional and unrepresentable values", arguments: [1.5, 1e100])
    func invalidThinkingBudget(_ budget: Double) async throws {
        let server = try BedrockTestServer()
        await #expect(throws: InvalidArgumentError.self) {
            _ = try await server.provider().chat(modelId: "anthropic.claude-3-haiku").doGenerate(options: .init(prompt: [], providerOptions: ["amazonBedrock": ["reasoningConfig": .object(["type": .string("enabled"), "budgetTokens": .number(budget)])]]))
        }
    }

    @Test("Usage sums exceeding Int remain unknown")
    func usageOverflow() async throws {
        let raw: JSONValue = .object(["inputTokens": .number(9e18), "outputTokens": .number(1), "totalTokens": .number(1.8e19), "cacheReadInputTokens": .number(9e18)])
        let server = try BedrockTestServer(json: .object(["output": .object(["message": .object(["role": .string("assistant"), "content": .array([])])]), "stopReason": .string("end_turn"), "usage": raw]))
        let usage = try await server.provider().chat(modelId: "model").doGenerate(options: .init(prompt: [])).usage
        #expect(usage.inputTokens.total == nil)
        #expect(usage.inputTokens.noCache == 9_000_000_000_000_000_000)
        #expect(usage.outputTokens.total == 1)
        #expect(usage.raw == raw)
    }

    actor RequestCapture {
        private(set) var request: URLRequest?
        func store(_ request: URLRequest) { self.request = request }
        func current() -> URLRequest? { request }
    }

    private let baseURL = "https://bedrock-runtime.us-east-1.amazonaws.com"
    private let modelId: BedrockChatModelId = "anthropic.claude-3-haiku-20240307-v1:0"

    private var testPrompt: LanguageModelV4Prompt {
        [
            .system(content: "System Prompt", providerOptions: nil),
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil),
        ]
    }

    private func normalizedHeaders(_ request: URLRequest) -> [String: String] {
        (request.allHTTPHeaderFields ?? [:]).reduce(into: [String: String]()) { result, pair in
            let key = pair.key.lowercased()
            if key == "user-agent" { return }
            result[key] = pair.value
        }
    }

    private func httpResponse(
        for request: URLRequest,
        statusCode: Int = 200,
        headers: [String: String] = [:]
    ) throws -> HTTPURLResponse {
        let url = try #require(request.url)
        return try #require(HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        ))
    }

    private func makeModel(
        modelId: BedrockChatModelId,
        headers: [String: String?] = [:],
        fetch: @escaping FetchFunction
    ) -> BedrockChatLanguageModel {
        createAmazonBedrock(settings: .init(region: "us-east-1", apiKey: "test-key", baseURL: baseURL, headers: headers.compactMapValues { $0 }, fetch: fetch, generateId: { "test-id" })).chat(modelId: modelId)
    }

    private func decodeRequestJSON(_ request: URLRequest) -> [String: Any]? {
        guard let body = request.httpBody,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return nil
        }
        return json
    }

    private func parseHTTPDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        formatter.timeZone = TimeZone(abbreviation: "GMT")
        return formatter.date(from: value)
    }

    @Test("doStream streams text deltas and maps usage")
    func doStreamStreamsTextAndUsage() async throws {
        let capture = RequestCapture()

        let frames = try [
            BedrockTestEventStream.jsonMessage(
                eventType: "contentBlockDelta",
                payload: [
                    "contentBlockIndex": 0,
                    "delta": ["text": "Hello"]
                ]
            ),
            BedrockTestEventStream.jsonMessage(
                eventType: "contentBlockDelta",
                payload: [
                    "contentBlockIndex": 1,
                    "delta": ["text": ", "]
                ]
            ),
            BedrockTestEventStream.jsonMessage(
                eventType: "contentBlockDelta",
                payload: [
                    "contentBlockIndex": 2,
                    "delta": ["text": "World!"]
                ]
            ),
            BedrockTestEventStream.jsonMessage(
                eventType: "metadata",
                payload: [
                    "usage": [
                        "inputTokens": 4,
                        "outputTokens": 34,
                        "totalTokens": 38,
                        "metrics": ["latencyMs": 10],
                    ],
                ]
            ),
            BedrockTestEventStream.jsonMessage(
                eventType: "messageStop",
                payload: [
                    "stopReason": "stop_sequence",
                ]
            ),
        ]

        let fetch: FetchFunction = { request in
            await capture.store(request)
            let http = try self.httpResponse(for: request, headers: ["content-type": "application/vnd.amazon.eventstream"])
            return FetchResponse(body: .stream(BedrockTestEventStream.makeStream(frames)), urlResponse: http)
        }

        let model = makeModel(modelId: modelId, fetch: fetch)
        let result = try await model.doStream(options: .init(prompt: testPrompt, includeRawChunks: false))
        let parts = try await convertReadableStreamToArray(result.stream)

        let expectedUsage = LanguageModelV4Usage(
            inputTokens: .init(total: 4, noCache: 4, cacheRead: 0, cacheWrite: 0),
            outputTokens: .init(total: 34, text: 34, reasoning: nil),
            raw: .object(["inputTokens": .number(4), "outputTokens": .number(34), "totalTokens": .number(38), "metrics": .object(["latencyMs": .number(10)])])
        )

        #expect(parts == [
            .streamStart(warnings: []),
            .responseMetadata(id: nil, modelId: modelId.rawValue, timestamp: nil),
            .textStart(id: "0", providerMetadata: nil),
            .textDelta(id: "0", delta: "Hello", providerMetadata: nil),
            .textStart(id: "1", providerMetadata: nil),
            .textDelta(id: "1", delta: ", ", providerMetadata: nil),
            .textStart(id: "2", providerMetadata: nil),
            .textDelta(id: "2", delta: "World!", providerMetadata: nil),
            .finish(
                finishReason: .init(unified: .stop, raw: "stop_sequence"),
                usage: expectedUsage,
                providerMetadata: nil
            ),
        ])

        guard let request = await capture.current(),
              let body = decodeRequestJSON(request) else {
            Issue.record("Missing request capture")
            return
        }

        #expect(request.url?.absoluteString == "\(baseURL)/model/\(modelId.rawValue.replacingOccurrences(of: ":", with: "%3A"))/converse-stream")
        #expect(body["system"] != nil)
        #expect(body["messages"] != nil)
        #expect(body["additionalModelResponseFieldPaths"] as? [String] == ["/delta/stop_sequence"])
    }

    @Test("doStream extracts response metadata from headers")
    func doStreamExtractsResponseMetadata() async throws {
        let responseHeaders: [String: String] = [
            "x-amzn-requestid": "test-request-id",
            "date": "Wed, 01 Jan 2025 00:00:00 GMT",
        ]

        let fetch: FetchFunction = { request in
            let http = try self.httpResponse(for: request, headers: responseHeaders)
            let frames = try [
                BedrockTestEventStream.jsonMessage(
                    eventType: "messageStop",
                    payload: ["stopReason": "end_turn"]
                )
            ]
            return FetchResponse(body: .stream(BedrockTestEventStream.makeStream(frames)), urlResponse: http)
        }

        let model = makeModel(modelId: modelId, fetch: fetch)
        let result = try await model.doStream(options: .init(prompt: testPrompt, includeRawChunks: false))
        let parts = try await convertReadableStreamToArray(result.stream)

        let expectedDate = try #require(parseHTTPDate("Wed, 01 Jan 2025 00:00:00 GMT"))
        let metadata = parts.first { part in
            if case .responseMetadata = part { return true }
            return false
        }

        #expect(metadata == .responseMetadata(id: "test-request-id", modelId: modelId.rawValue, timestamp: expectedDate))
        #expect(result.response?.headers?["x-amzn-requestid"] == "test-request-id")
        #expect(result.response?.headers?["date"] == "Wed, 01 Jan 2025 00:00:00 GMT")
    }

    @Test("doStream streams tool deltas and emits tool calls")
    func doStreamStreamsToolDeltas() async throws {
        let frames = try [
            BedrockTestEventStream.jsonMessage(
                eventType: "contentBlockStart",
                payload: [
                    "contentBlockIndex": 0,
                    "start": [
                        "toolUse": [
                            "toolUseId": "tool-use-id",
                            "name": "test-tool",
                        ],
                    ],
                ]
            ),
            BedrockTestEventStream.jsonMessage(
                eventType: "contentBlockDelta",
                payload: [
                    "contentBlockIndex": 0,
                    "delta": [
                        "toolUse": [
                            "input": "{\"value\":"
                        ]
                    ],
                ]
            ),
            BedrockTestEventStream.jsonMessage(
                eventType: "contentBlockDelta",
                payload: [
                    "contentBlockIndex": 0,
                    "delta": [
                        "toolUse": [
                            "input": "\"Sparkle Day\"}"
                        ]
                    ],
                ]
            ),
            BedrockTestEventStream.jsonMessage(
                eventType: "contentBlockStop",
                payload: [
                    "contentBlockIndex": 0,
                ]
            ),
            BedrockTestEventStream.jsonMessage(
                eventType: "messageStop",
                payload: [
                    "stopReason": "tool_use",
                ]
            ),
        ]

        let fetch: FetchFunction = { request in
            let http = try self.httpResponse(for: request)
            return FetchResponse(body: .stream(BedrockTestEventStream.makeStream(frames)), urlResponse: http)
        }

        let model = makeModel(modelId: modelId, fetch: fetch)
        let tools: [LanguageModelV4Tool] = [
            .function(.init(
                name: "test-tool",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object(["value": .object(["type": .string("string")])]),
                    "required": .array([.string("value")]),
                    "additionalProperties": .bool(false),
                ])
            ))
        ]

        let result = try await model.doStream(options: .init(
            prompt: testPrompt,
            tools: tools,
            toolChoice: .tool(toolName: "test-tool"),
            includeRawChunks: false
        ))

        let parts = try await convertReadableStreamToArray(result.stream)

        #expect(parts.contains(.toolCall(.init(
            toolCallId: "tool-use-id",
            toolName: "test-tool",
            input: "{\"value\":\"Sparkle Day\"}"
        ))))

        let finish = parts.last { part in
            if case .finish = part { return true }
            return false
        }

        #expect(finish == .finish(
            finishReason: .init(unified: .toolCalls, raw: "tool_use"),
            usage: .init(),
            providerMetadata: nil
        ))
    }

    @Test("json response format with schema adds json tool and returns json tool output as text")
    func jsonResponseFormatWithSchemaUsesJsonTool() async throws {
        let frames = try [
            BedrockTestEventStream.jsonMessage(
                eventType: "contentBlockStart",
                payload: [
                    "contentBlockIndex": 0,
                    "start": [
                        "toolUse": [
                            "toolUseId": "tool-use-id",
                            "name": "json",
                        ],
                    ],
                ]
            ),
            BedrockTestEventStream.jsonMessage(
                eventType: "contentBlockDelta",
                payload: [
                    "contentBlockIndex": 0,
                    "delta": [
                        "toolUse": [
                            "input": "{\"value\":42}"
                        ]
                    ],
                ]
            ),
            BedrockTestEventStream.jsonMessage(
                eventType: "contentBlockStop",
                payload: ["contentBlockIndex": 0]
            ),
            BedrockTestEventStream.jsonMessage(
                eventType: "messageStop",
                payload: ["stopReason": "tool_use"]
            ),
        ]

        let fetch: FetchFunction = { request in
            let http = try self.httpResponse(for: request)
            return FetchResponse(body: .stream(BedrockTestEventStream.makeStream(frames)), urlResponse: http)
        }

        let model = makeModel(modelId: modelId, fetch: fetch)
        let schema: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([
                "value": .object(["type": .string("number")]),
            ]),
            "required": .array([.string("value")]),
            "additionalProperties": .bool(false),
        ])

        let result = try await model.doStream(options: .init(
            prompt: testPrompt,
            responseFormat: .json(schema: schema, name: nil, description: nil),
            includeRawChunks: false
        ))

        let parts = try await convertReadableStreamToArray(result.stream)

        #expect(parts.contains(.textDelta(id: "0", delta: "{\"value\":42}", providerMetadata: nil)))

        let finish = parts.last { part in
            if case .finish = part { return true }
            return false
        }

        #expect(finish == .finish(
            finishReason: .init(unified: .stop, raw: "tool_use"),
            usage: .init(),
            providerMetadata: [
                "amazonBedrock": [
                    "isJsonResponseFromTool": .bool(true),
                    "stopSequence": .null,
                ],
                "bedrock": [
                    "isJsonResponseFromTool": .bool(true),
                    "stopSequence": .null,
                ]
            ]
        ))
    }
}
