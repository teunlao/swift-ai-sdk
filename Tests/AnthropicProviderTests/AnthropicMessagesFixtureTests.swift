import Foundation
import Testing
@testable import AnthropicProvider
import AISDKProvider
import AISDKProviderUtils

@Suite("AnthropicMessages fixture scenarios")
struct AnthropicMessagesFixtureTests {
    private let messagesURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private let samplePrompt: LanguageModelV3Prompt = [
        .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
    ]

    private actor RequestCapture {
        private(set) var request: URLRequest?

        func store(_ request: URLRequest) {
            self.request = request
        }

        func current() -> URLRequest? {
            request
        }
    }

    private func fixturesDirectory() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("external/vercel-ai-sdk/packages/anthropic/src/__fixtures__")
    }

    private func loadJSONFixtureData(_ name: String) throws -> Data {
        let url = fixturesDirectory().appendingPathComponent("\(name).json")
        return try Data(contentsOf: url)
    }

    private func loadChunksFixture(_ name: String) throws -> [String] {
        let url = fixturesDirectory().appendingPathComponent("\(name).chunks.txt")
        let text = try String(contentsOf: url, encoding: .utf8)
        var chunks = text
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { "data: \($0)\n\n" }
        chunks.append("data: [DONE]\n\n")
        return chunks
    }

    private func makeConfig(fetch: @escaping FetchFunction) -> AnthropicMessagesConfig {
        AnthropicMessagesConfig(
            provider: "anthropic.messages",
            baseURL: "https://api.anthropic.com/v1",
            headers: {
                [
                    "x-api-key": "test-key",
                    "anthropic-version": "2023-06-01"
                ]
            },
            fetch: fetch,
            supportedUrls: { [:] },
            generateId: { "generated-id" }
        )
    }

    private func makeJSONFetch(
        fixture name: String,
        capture: RequestCapture? = nil
    ) throws -> FetchFunction {
        let responseData = try loadJSONFixtureData(name)
        let response = HTTPURLResponse(
            url: messagesURL,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        return { request in
            if let capture {
                await capture.store(request)
            }

            return FetchResponse(body: .data(responseData), urlResponse: response)
        }
    }

    private func makeStreamFetch(
        fixture name: String,
        capture: RequestCapture? = nil
    ) throws -> FetchFunction {
        let chunks = try loadChunksFixture(name)
        let response = HTTPURLResponse(
            url: messagesURL,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!

        return { request in
            if let capture {
                await capture.store(request)
            }

            let stream = AsyncThrowingStream<Data, Error> { continuation in
                for chunk in chunks {
                    continuation.yield(Data(chunk.utf8))
                }
                continuation.finish()
            }

            return FetchResponse(body: .stream(stream), urlResponse: response)
        }
    }

    private func decodeRequestBody(_ request: URLRequest?) -> [String: Any]? {
        guard let data = request?.httpBody else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func anthropicBetaSet(_ request: URLRequest?) -> Set<String>? {
        guard let request else { return nil }
        let headers = request.allHTTPHeaderFields ?? [:]
        guard let value = headers["anthropic-beta"] else { return nil }
        let parts = value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return Set(parts)
    }

    private func decodeJSONValue(_ string: String) -> JSONValue? {
        guard let data = string.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }

    private func collectParts(
        from stream: AsyncThrowingStream<LanguageModelV3StreamPart, Error>
    ) async throws -> [LanguageModelV3StreamPart] {
        var parts: [LanguageModelV3StreamPart] = []
        for try await part in stream {
            parts.append(part)
        }
        return parts
    }

    private var expectedMCPMetadata: SharedV3ProviderMetadata {
        [
            "anthropic": [
                "type": .string("mcp-tool-use"),
                "serverName": .string("echo")
            ]
        ]
    }

    private var expectedMCPToolResultContent: JSONValue {
        .array([
            .object([
                "type": .string("text"),
                "text": .string("Tool echo: hello world")
            ])
        ])
    }

    private func makeMCPProviderOptions() -> SharedV3ProviderOptions {
        [
            "anthropic": [
                "mcpServers": .array([
                    .object([
                        "type": .string("url"),
                        "name": .string("echo"),
                        "url": .string("https://echo.mcp.inevitable.fyi/mcp")
                    ])
                ])
            ]
        ]
    }

    private func makeWebFetchTools() -> [LanguageModelV3Tool] {
        [
            .provider(.init(
                id: "anthropic.web_fetch_20260209",
                name: "web_fetch",
                args: [:]
            )),
            .provider(.init(
                id: "anthropic.code_execution_20260120",
                name: "code_execution",
                args: [:]
            ))
        ]
    }

    @Test("doGenerate decodes MCP server fixture")
    func generateMCPFixture() async throws {
        let capture = RequestCapture()
        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeConfig(fetch: try makeJSONFetch(fixture: "anthropic-mcp.1", capture: capture))
        )

        let result = try await model.doGenerate(options: .init(
            prompt: samplePrompt,
            providerOptions: makeMCPProviderOptions()
        ))

        let request = await capture.current()
        let json = decodeRequestBody(request)
        if let servers = json?["mcp_servers"] as? [[String: Any]],
           let first = servers.first {
            #expect(servers.count == 1)
            #expect(first["type"] as? String == "url")
            #expect(first["name"] as? String == "echo")
            #expect(first["url"] as? String == "https://echo.mcp.inevitable.fyi/mcp")
        } else {
            Issue.record("Expected mcp_servers payload")
        }
        #expect(anthropicBetaSet(request) == Set(["mcp-client-2025-04-04"]))

        #expect(result.response?.id == "msg_01P81KJc28LkYyoDAYG1bWVb")
        #expect(result.response?.modelId == "claude-sonnet-4-5-20250929")
        #expect(result.finishReason.unified == LanguageModelV3FinishReason.Unified.stop)
        #expect(result.usage.inputTokens.total == 1250)
        #expect(result.usage.outputTokens.total == 88)

        let toolCalls = result.content.compactMap { item -> LanguageModelV3ToolCall? in
            guard case .toolCall(let call) = item else { return nil }
            return call
        }
        #expect(toolCalls.count == 1)
        #expect(toolCalls.first?.toolCallId == "mcptoolu_015oTj2fXVKLrDohFetJd5UL")
        #expect(toolCalls.first?.toolName == "echo")
        #expect(toolCalls.first?.providerExecuted == true)
        #expect(toolCalls.first?.dynamic == true)
        #expect(decodeJSONValue(toolCalls.first?.input ?? "") == .object([
            "message": .string("hello world")
        ]))
        #expect(toolCalls.first?.providerMetadata == expectedMCPMetadata)

        let toolResults = result.content.compactMap { item -> LanguageModelV3ToolResult? in
            guard case .toolResult(let toolResult) = item else { return nil }
            return toolResult
        }
        #expect(toolResults.count == 1)
        #expect(toolResults.first?.toolCallId == "mcptoolu_015oTj2fXVKLrDohFetJd5UL")
        #expect(toolResults.first?.toolName == "echo")
        #expect(toolResults.first?.isError == false)
        #expect(toolResults.first?.dynamic == true)
        #expect(toolResults.first?.providerMetadata == expectedMCPMetadata)
        #expect(toolResults.first?.result == expectedMCPToolResultContent)

        let text = result.content.compactMap { item -> String? in
            guard case .text(let part) = item else { return nil }
            return part.text
        }.joined()
        #expect(text.contains("The echo tool responded back with"))
    }

    @Test("doStream emits MCP server fixture events")
    func streamMCPFixture() async throws {
        let capture = RequestCapture()
        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-3-haiku-20240307"),
            config: makeConfig(fetch: try makeStreamFetch(fixture: "anthropic-mcp.1", capture: capture))
        )

        let result = try await model.doStream(options: .init(
            prompt: samplePrompt,
            providerOptions: makeMCPProviderOptions()
        ))
        let parts = try await collectParts(from: result.stream)

        let request = await capture.current()
        #expect(anthropicBetaSet(request) == Set([
            "fine-grained-tool-streaming-2025-05-14",
            "mcp-client-2025-04-04"
        ]))

        let toolCalls = parts.compactMap { part -> LanguageModelV3ToolCall? in
            guard case .toolCall(let call) = part else { return nil }
            return call
        }
        #expect(toolCalls.count == 1)
        #expect(toolCalls.first?.toolCallId == "mcptoolu_017CuqaJcXe5ZHJjaz3KS1AT")
        #expect(toolCalls.first?.toolName == "echo")
        #expect(toolCalls.first?.providerExecuted == true)
        #expect(toolCalls.first?.dynamic == true)
        #expect(decodeJSONValue(toolCalls.first?.input ?? "") == .object([
            "message": .string("hello world")
        ]))
        #expect(toolCalls.first?.providerMetadata == expectedMCPMetadata)

        let toolResults = parts.compactMap { part -> LanguageModelV3ToolResult? in
            guard case .toolResult(let toolResult) = part else { return nil }
            return toolResult
        }
        #expect(toolResults.count == 1)
        #expect(toolResults.first?.toolCallId == "mcptoolu_017CuqaJcXe5ZHJjaz3KS1AT")
        #expect(toolResults.first?.toolName == "echo")
        #expect(toolResults.first?.isError == false)
        #expect(toolResults.first?.dynamic == true)
        #expect(toolResults.first?.providerMetadata == expectedMCPMetadata)
        #expect(toolResults.first?.result == expectedMCPToolResultContent)

        let streamedText = parts.compactMap { part -> String? in
            guard case .textDelta(_, let delta, _) = part else { return nil }
            return delta
        }.joined()
        #expect(streamedText == "The echo tool responded back with: **hello world**\n\nIt simply echoed back the exact message that was sent to it.")

        if let finishPart = parts.last(where: { if case .finish = $0 { return true } else { return false } }),
           case .finish(let finishReason, let usage, _) = finishPart {
            #expect(finishReason.unified == LanguageModelV3FinishReason.Unified.stop)
            #expect(usage.inputTokens.total == 1250)
            #expect(usage.outputTokens.total == 83)
        } else {
            Issue.record("Expected finish part")
        }
    }

    @Test("doGenerate decodes web fetch 20260209 fixture")
    func generateWebFetch20260209Fixture() async throws {
        let capture = RequestCapture()
        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-sonnet-4-6"),
            config: makeConfig(fetch: try makeJSONFetch(fixture: "anthropic-web-fetch-tool-20260209.1", capture: capture))
        )

        let result = try await model.doGenerate(options: .init(
            prompt: samplePrompt,
            tools: makeWebFetchTools()
        ))

        let request = await capture.current()
        let json = decodeRequestBody(request)
        if let tools = json?["tools"] as? [[String: Any]] {
            #expect(tools.count == 2)
            #expect(tools[0]["type"] as? String == "web_fetch_20260209")
            #expect(tools[0]["name"] as? String == "web_fetch")
            #expect(tools[1]["type"] as? String == "code_execution_20260120")
            #expect(tools[1]["name"] as? String == "code_execution")
        } else {
            Issue.record("Expected tools payload")
        }
        #expect(anthropicBetaSet(request) == Set(["code-execution-web-tools-2026-02-09"]))

        #expect(result.response?.id == "msg_012HMyuvZLN3vLPPuRYVnQff")
        #expect(result.response?.modelId == "claude-sonnet-4-6")
        #expect(result.finishReason.unified == LanguageModelV3FinishReason.Unified.stop)
        #expect(result.usage.inputTokens.total == 7204)
        #expect(result.usage.outputTokens.total == 162)

        let codeExecutionCall = result.content.compactMap { item -> LanguageModelV3ToolCall? in
            guard case .toolCall(let call) = item, call.toolCallId == "srvtoolu_015CSHH7X69AhdK9gNzotEeh" else { return nil }
            return call
        }.first
        #expect(codeExecutionCall?.toolName == "code_execution")
        #expect(codeExecutionCall?.providerExecuted == true)
        #expect(decodeJSONValue(codeExecutionCall?.input ?? "") == .object([
            "code": .string("\nimport json\nresult = await web_fetch({\"url\": \"https://example.com\"})\nparsed = json.loads(result) if isinstance(result, str) else result\nif isinstance(parsed, list):\n    print(parsed[0][\"content\"][:500])\nelse:\n    print(parsed)\n"),
            "type": .string("programmatic-tool-call")
        ]))

        let webFetchCall = result.content.compactMap { item -> LanguageModelV3ToolCall? in
            guard case .toolCall(let call) = item, call.toolCallId == "srvtoolu_0152eMmZnBDZc4C2miykFWW5" else { return nil }
            return call
        }.first
        #expect(webFetchCall?.toolName == "web_fetch")
        #expect(webFetchCall?.providerExecuted == true)
        #expect(decodeJSONValue(webFetchCall?.input ?? "") == .object([
            "url": .string("https://example.com")
        ]))
        #expect(webFetchCall?.providerMetadata == nil)

        let toolResults = result.content.compactMap { item -> LanguageModelV3ToolResult? in
            guard case .toolResult(let toolResult) = item else { return nil }
            return toolResult
        }
        #expect(toolResults.count == 2)

        let webFetchResult = toolResults.first { $0.toolCallId == "srvtoolu_0152eMmZnBDZc4C2miykFWW5" }
        #expect(webFetchResult?.toolName == "web_fetch")
        if case .object(let payload)? = webFetchResult?.result {
            #expect(payload["type"] == .string("web_fetch_result"))
            #expect(payload["url"] == .string("https://example.com"))
            #expect(payload["retrievedAt"] == .string("2026-03-03T15:05:04.091000+00:00"))
            if case .object(let content) = payload["content"] {
                #expect(content["type"] == .string("document"))
                #expect(content["title"] == .string("Example Domain"))
                if case .object(let source) = content["source"] {
                    #expect(source["type"] == .string("text"))
                    #expect(source["mediaType"] == .string("text/plain"))
                    if case .string(let data) = source["data"] {
                        #expect(data.contains("Example Domain"))
                    } else {
                        Issue.record("Expected web fetch source data")
                    }
                } else {
                    Issue.record("Expected web fetch source object")
                }
            } else {
                Issue.record("Expected web fetch content object")
            }
        } else {
            Issue.record("Expected web fetch result payload")
        }

        let codeExecutionResult = toolResults.first { $0.toolCallId == "srvtoolu_015CSHH7X69AhdK9gNzotEeh" }
        #expect(codeExecutionResult?.toolName == "code_execution")
        if case .object(let payload)? = codeExecutionResult?.result {
            #expect(payload["type"] == .string("code_execution_result"))
            if case .string(let stdout) = payload["stdout"] {
                #expect(stdout.contains("web_fetch_result"))
                #expect(stdout.contains("Example Domain"))
            } else {
                Issue.record("Expected code execution stdout")
            }
        } else {
            Issue.record("Expected code execution result payload")
        }

        let text = result.content.compactMap { item -> String? in
            guard case .text(let part) = item else { return nil }
            return part.text
        }.joined()
        #expect(text.contains("placeholder page"))
        #expect(result.providerMetadata?["anthropic"]?["container"] == .object([
            "id": .string("container_011CYgdc3J4LpgHCdaYF6kB6"),
            "expiresAt": .string("2026-03-03T19:37:31.023014Z"),
            "skills": .null
        ]))
    }

    @Test("doStream emits web fetch 20260209 events")
    func streamWebFetch20260209Fixture() async throws {
        let capture = RequestCapture()
        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-sonnet-4-6"),
            config: makeConfig(fetch: try makeStreamFetch(fixture: "anthropic-web-fetch-tool-20260209.1", capture: capture))
        )

        let result = try await model.doStream(options: .init(
            prompt: samplePrompt,
            tools: makeWebFetchTools()
        ))
        let parts = try await collectParts(from: result.stream)

        let request = await capture.current()
        #expect(anthropicBetaSet(request) == Set([
            "code-execution-web-tools-2026-02-09",
            "fine-grained-tool-streaming-2025-05-14"
        ]))

        let toolCalls = parts.compactMap { part -> LanguageModelV3ToolCall? in
            guard case .toolCall(let call) = part else { return nil }
            return call
        }
        #expect(toolCalls.count == 2)

        let codeExecutionCall = toolCalls.first { $0.toolCallId == "srvtoolu_01LKcA5qc1HwvLQSe3cLKmcK" }
        #expect(codeExecutionCall?.toolName == "code_execution")
        #expect(codeExecutionCall?.providerExecuted == true)
        #expect(decodeJSONValue(codeExecutionCall?.input ?? "") == .object([
            "code": .string("\nimport json\nresult = await web_fetch({\"url\": \"https://example.com\"})\nif isinstance(result, list):\n    print(result[0][\"content\"][:500])\nelse:\n    print(result)\n"),
            "type": .string("programmatic-tool-call")
        ]))

        let webFetchCall = toolCalls.first { $0.toolCallId == "srvtoolu_01SyXFZ4vqqE144ySoN6b5UG" }
        #expect(webFetchCall?.toolName == "web_fetch")
        #expect(webFetchCall?.providerExecuted == true)
        #expect(decodeJSONValue(webFetchCall?.input ?? "") == .object([
            "url": .string("https://example.com")
        ]))
        #expect(webFetchCall?.providerMetadata == nil)

        let toolResults = parts.compactMap { part -> LanguageModelV3ToolResult? in
            guard case .toolResult(let toolResult) = part else { return nil }
            return toolResult
        }
        #expect(toolResults.count == 2)

        let webFetchResult = toolResults.first { $0.toolCallId == "srvtoolu_01SyXFZ4vqqE144ySoN6b5UG" }
        #expect(webFetchResult?.toolName == "web_fetch")
        if case .object(let payload)? = webFetchResult?.result {
            #expect(payload["type"] == .string("web_fetch_result"))
            if case .object(let content) = payload["content"] {
                #expect(content["title"] == .string("Example Domain"))
            } else {
                Issue.record("Expected web fetch document content")
            }
        } else {
            Issue.record("Expected web fetch result payload")
        }

        let codeExecutionResult = toolResults.first { $0.toolCallId == "srvtoolu_01LKcA5qc1HwvLQSe3cLKmcK" }
        #expect(codeExecutionResult?.toolName == "code_execution")
        if case .object(let payload)? = codeExecutionResult?.result {
            #expect(payload["type"] == .string("code_execution_result"))
            if case .string(let stdout) = payload["stdout"] {
                #expect(stdout.contains("\"type\": \"web_fetch_result\""))
                #expect(stdout.contains("\"title\": \"Example Domain\""))
            } else {
                Issue.record("Expected streamed code execution stdout")
            }
        } else {
            Issue.record("Expected streamed code execution result payload")
        }

        let streamedText = parts.compactMap { part -> String? in
            guard case .textDelta(_, let delta, _) = part else { return nil }
            return delta
        }.joined()
        #expect(streamedText == "The page at **example.com** is a simple placeholder page explaining that the domain is reserved for use in illustrative documentation examples and does not require prior permission to reference.")

        if let finishPart = parts.last(where: { if case .finish = $0 { return true } else { return false } }),
           case .finish(let finishReason, let usage, let metadata) = finishPart {
            #expect(finishReason.unified == LanguageModelV3FinishReason.Unified.stop)
            #expect(usage.inputTokens.total == 7172)
            #expect(usage.outputTokens.total == 144)
            #expect(metadata?["anthropic"]?["container"] == .object([
                "id": .string("container_011CYgdezfe66pcmCprMd28x"),
                "expiresAt": .string("2026-03-03T19:38:14.861782Z"),
                "skills": .null
            ]))
        } else {
            Issue.record("Expected finish part")
        }
    }
}
