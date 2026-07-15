import Foundation
import Testing
@testable import AnthropicProvider
import AISDKProvider
import AISDKProviderUtils

private let advisorPrompt: LanguageModelV3Prompt = [
    .user(content: [.text(.init(text: "Review this design"))], providerOptions: nil)
]

private actor AdvisorRequestCapture {
    private var request: URLRequest?

    func store(_ request: URLRequest) {
        self.request = request
    }

    func value() -> URLRequest? {
        request
    }
}

private func advisorConfig(fetch: @escaping FetchFunction) -> AnthropicMessagesConfig {
    AnthropicMessagesConfig(
        provider: "anthropic.messages",
        baseURL: "https://api.anthropic.com/v1",
        headers: { [
            "x-api-key": "test-key",
            "anthropic-version": "2023-06-01",
        ] },
        fetch: fetch,
        supportedUrls: { [:] },
        generateId: { "generated-id" }
    )
}

private func advisorTool() -> LanguageModelV3Tool {
    .provider(.init(
        id: "anthropic.advisor_20260301",
        name: "advisor",
        args: ["model": .string("claude-opus-4-7")]
    ))
}

private func advisorHTTPResponse() -> HTTPURLResponse {
    HTTPURLResponse(
        url: URL(string: "https://api.anthropic.com/v1/messages")!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
    )!
}

private func advisorStream(_ payloads: [String]) -> AsyncThrowingStream<Data, Error> {
    AsyncThrowingStream { continuation in
        for payload in payloads {
            continuation.yield(Data("data: \(payload)\n\n".utf8))
        }
        continuation.finish()
    }
}

@Suite("Anthropic advisor_20260301")
struct AnthropicAdvisorTests {
    @Test("sends advisor tool and maps all result variants")
    func generateAdvisorResults() async throws {
        let capture = AdvisorRequestCapture()
        let responseJSON: [String: Any] = [
            "type": "message",
            "id": "msg_advisor",
            "model": "claude-sonnet-4-6",
            "content": [
                [
                    "type": "server_tool_use",
                    "id": "advisor-plain",
                    "name": "advisor",
                    "input": [:],
                ],
                [
                    "type": "advisor_tool_result",
                    "tool_use_id": "advisor-plain",
                    "content": [
                        "type": "advisor_result",
                        "text": "Define shutdown semantics before implementation.",
                    ],
                ],
                [
                    "type": "server_tool_use",
                    "id": "advisor-redacted",
                    "name": "advisor",
                    "input": [:],
                ],
                [
                    "type": "advisor_tool_result",
                    "tool_use_id": "advisor-redacted",
                    "content": [
                        "type": "advisor_redacted_result",
                        "encrypted_content": "opaque-encrypted-advice",
                    ],
                ],
                [
                    "type": "server_tool_use",
                    "id": "advisor-error",
                    "name": "advisor",
                    "input": [:],
                ],
                [
                    "type": "advisor_tool_result",
                    "tool_use_id": "advisor-error",
                    "content": [
                        "type": "advisor_tool_result_error",
                        "error_code": "max_uses_exceeded",
                    ],
                ],
                ["type": "text", "text": "Final design"],
            ],
            "stop_reason": "end_turn",
            "stop_sequence": NSNull(),
            "usage": [
                "input_tokens": 20,
                "output_tokens": 35,
                "iterations": [
                    ["type": "message", "input_tokens": 10, "output_tokens": 5],
                    [
                        "type": "advisor_message",
                        "model": "claude-opus-4-7",
                        "input_tokens": 100,
                        "output_tokens": 20,
                    ],
                    ["type": "message", "input_tokens": 20, "output_tokens": 35],
                ],
            ],
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: advisorHTTPResponse())
        }
        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-sonnet-4-6"),
            config: advisorConfig(fetch: fetch)
        )

        let result = try await model.doGenerate(options: .init(
            prompt: advisorPrompt,
            tools: [advisorTool()]
        ))

        let request = try #require(await capture.value())
        let body = try #require(request.httpBody)
        let requestJSON = try #require(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        let tools = try #require(requestJSON["tools"] as? [[String: Any]])
        #expect(tools.count == 1)
        #expect(tools[0]["type"] as? String == "advisor_20260301")
        #expect(tools[0]["name"] as? String == "advisor")
        #expect(tools[0]["model"] as? String == "claude-opus-4-7")
        #expect(request.allHTTPHeaderFields?["anthropic-beta"] == "advisor-tool-2026-03-01")

        let calls = result.content.compactMap { part -> LanguageModelV3ToolCall? in
            if case .toolCall(let call) = part { return call }
            return nil
        }
        #expect(calls.count == 3)
        #expect(calls.allSatisfy {
            $0.toolName == "advisor" && $0.input == "{}" && $0.providerExecuted == true
        })

        let results = result.content.compactMap { part -> LanguageModelV3ToolResult? in
            if case .toolResult(let result) = part { return result }
            return nil
        }
        #expect(results.count == 3)
        #expect(results[0].result == .object([
            "type": .string("advisor_result"),
            "text": .string("Define shutdown semantics before implementation."),
        ]))
        #expect(results[1].result == .object([
            "type": .string("advisor_redacted_result"),
            "encryptedContent": .string("opaque-encrypted-advice"),
        ]))
        #expect(results[2].isError == true)
        #expect(results[2].result == .object([
            "type": .string("advisor_tool_result_error"),
            "errorCode": .string("max_uses_exceeded"),
        ]))
        #expect(result.usage.inputTokens.noCache == 30)
        #expect(result.usage.outputTokens.total == 40)
    }

    @Test("streams advisor result before executor text resumes")
    func streamAdvisorResultOrdering() async throws {
        let payloads = [
            #"{"type":"message_start","message":{"id":"msg_advisor","type":"message","role":"assistant","model":"claude-sonnet-4-6","content":[],"stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":10,"output_tokens":0}}}"#,
            #"{"type":"content_block_start","index":0,"content_block":{"type":"server_tool_use","id":"advisor-plain","name":"advisor","input":{}}}"#,
            #"{"type":"content_block_stop","index":0}"#,
            #"{"type":"content_block_start","index":1,"content_block":{"type":"advisor_tool_result","tool_use_id":"advisor-plain","content":{"type":"advisor_result","text":"Define shutdown semantics first."}}}"#,
            #"{"type":"content_block_stop","index":1}"#,
            #"{"type":"content_block_start","index":2,"content_block":{"type":"text","text":""}}"#,
            #"{"type":"content_block_delta","index":2,"delta":{"type":"text_delta","text":"Final design"}}"#,
            #"{"type":"content_block_stop","index":2}"#,
            #"{"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"input_tokens":20,"output_tokens":35,"iterations":[{"type":"message","input_tokens":10,"output_tokens":5},{"type":"advisor_message","model":"claude-opus-4-7","input_tokens":100,"output_tokens":20},{"type":"message","input_tokens":20,"output_tokens":35}]}}"#,
            #"{"type":"message_stop"}"#,
        ]
        let fetch: FetchFunction = { _ in
            FetchResponse(body: .stream(advisorStream(payloads)), urlResponse: advisorHTTPResponse())
        }
        let model = AnthropicMessagesLanguageModel(
            modelId: .init(rawValue: "claude-sonnet-4-6"),
            config: advisorConfig(fetch: fetch)
        )

        let result = try await model.doStream(options: .init(
            prompt: advisorPrompt,
            tools: [advisorTool()]
        ))
        var parts: [LanguageModelV3StreamPart] = []
        for try await part in result.stream {
            parts.append(part)
        }

        let callIndex = try #require(parts.firstIndex { part in
            if case .toolCall(let call) = part { return call.toolName == "advisor" }
            return false
        })
        let resultIndex = try #require(parts.firstIndex { part in
            if case .toolResult(let result) = part { return result.toolName == "advisor" }
            return false
        })
        let textStartIndex = try #require(parts.firstIndex { part in
            if case .textStart(let id, _) = part { return id == "2" }
            return false
        })
        #expect(callIndex < resultIndex)
        #expect(resultIndex < textStartIndex)

        if case .toolCall(let call) = parts[callIndex] {
            #expect(call.input == "{}")
            #expect(call.providerExecuted == true)
        }
        if case .toolResult(let advisorResult) = parts[resultIndex] {
            #expect(advisorResult.result == .object([
                "type": .string("advisor_result"),
                "text": .string("Define shutdown semantics first."),
            ]))
        }

        guard let finish = parts.last(where: {
            if case .finish = $0 { return true }
            return false
        }), case .finish(_, let usage, let metadata) = finish else {
            Issue.record("Missing finish part")
            return
        }
        #expect(usage.inputTokens.noCache == 30)
        #expect(usage.outputTokens.total == 40)
        if case .array(let iterations) = metadata?["anthropic"]?["iterations"] {
            #expect(iterations.count == 3)
        } else {
            Issue.record("Missing advisor iterations metadata")
        }
    }
}
