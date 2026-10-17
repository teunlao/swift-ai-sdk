import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import OpenAICompatibleProvider

@Suite("Compatible chat V4 contracts")
struct OpenAICompatibleChatContractsTests {
    actor Capture {
        var request: URLRequest?
        func store(_ value: URLRequest) { request = value }
        func value() -> URLRequest? { request }
    }
    private let prompt: LanguageModelV4Prompt = [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)]

    @Test func contentArraysPreserveTextAndThinkingOrder() async throws {
        let response: JSONValue = ["choices": [["message": ["content": [
            ["type": "thinking", "thinking": [["type": "text", "text": "Reason"], ["type": "future", "text": "ignored"]]],
            ["type": "text", "text": "Answer"], ["type": "future"]
        ]], "finish_reason": "stop"]]]
        let bytes = try JSONEncoder().encode(response)
        let fetch: FetchFunction = { request in
            FetchResponse(body: .data(bytes), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
        }
        let model = createOpenAICompatible(settings: .init(baseURL: "https://api.example.com", name: "custom", fetch: fetch))("model")
        let result = try await model.doGenerate(options: .init(prompt: prompt))
        #expect(result.content == [.reasoning(.init(text: "Reason")), .text(.init(text: "Answer"))])
    }

    @Test func missingFinishReasonFailsAndMetadataWaitsForIdentity() async throws {
        let chunks: [JSONValue] = [
            ["id": "", "model": "", "created": 0, "choices": [["delta": ["content": "First"]]]],
            ["id": "response-1", "choices": [["delta": ["content": [["type": "thinking", "thinking": [["type": "text", "text": "Reason"]]], ["type": "text", "text": "Last"]]]]]]
        ]
        let data = Data(try chunks.map { "data: " + String(decoding: try JSONEncoder().encode($0), as: UTF8.self) + "\n\n" }.joined().utf8)
        let fetch: FetchFunction = { request in
            FetchResponse(body: .data(data), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!)
        }
        let model = createOpenAICompatible(settings: .init(baseURL: "https://api.example.com", name: "custom", fetch: fetch))("model")
        let stream = try await model.doStream(options: .init(prompt: prompt)).stream
        var order: [String] = []
        var errors = 0
        for try await part in stream {
            switch part {
            case .responseMetadata(let id, _, _): #expect(id == "response-1"); order.append("metadata")
            case .textStart: order.append("text-start")
            case .textEnd: order.append("text-end")
            case .reasoningStart: order.append("reasoning-start")
            case .reasoningEnd: order.append("reasoning-end")
            case .error(.error(let error)):
                #expect(error is InvalidResponseDataError)
                errors += 1
            case .finish(let reason, _, _): #expect(reason.unified == .error)
            default: break
            }
        }
        #expect(errors == 1)
        #expect(order == ["text-start", "metadata", "text-end", "reasoning-start", "reasoning-end", "text-start", "text-end"])
    }

    @Test func bufferedToolsKeepFirstExtraContentAndRealResponseIdentity() async throws {
        let chunks: [JSONValue] = [
            ["id": "", "model": "", "created": 0, "choices": [["delta": ["tool_calls": [["index": 5, "id": "call", "extra_content": .object([:]), "function": ["arguments": "{"]]]]]]],
            ["id": "response", "choices": [["delta": ["tool_calls": [["index": 5, "extra_content": ["google": ["thought_signature": "later"]], "function": ["name": "lookup", "arguments": "}"]]]], "finish_reason": "tool_calls"]]]
        ]
        let bytes = Data(try chunks.map { "data: " + String(decoding: try JSONEncoder().encode($0), as: UTF8.self) + "\n\n" }.joined().utf8)
        let fetch: FetchFunction = { request in FetchResponse(body: .data(bytes), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!) }
        let model = createOpenAICompatible(settings: .init(baseURL: "https://api.example.com", name: "custom", fetch: fetch))("model")
        let stream = try await model.doStream(options: .init(prompt: [])).stream
        var calls: [LanguageModelV4ToolCall] = []
        var identities: [String] = []
        for try await part in stream {
            if case .toolCall(let call) = part { calls.append(call) }
            if case .responseMetadata(let id, _, _) = part, let id { identities.append(id) }
        }
        #expect(identities == ["response"])
        #expect(calls.count == 1)
        #expect(calls.first?.input == "{}")
        #expect(calls.first?.providerMetadata == nil)
    }

    @Test func referencesVideoAndMultipartToolContentReachTransport() async throws {
        let capture = Capture()
        let data = Data(#"{"choices":[{"message":{"content":"Answer"},"finish_reason":"stop"}]}"#.utf8)
        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(data), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
        }
        let model = createOpenAICompatible(settings: .init(baseURL: "https://api.example.com", name: "custom", fetch: fetch, supportsMultiPartToolContent: true))("model")
        let messages: LanguageModelV4Prompt = [
            .user(content: [.file(.init(data: .reference(["custom": "file-1"]), mediaType: "application/pdf")),
                            .file(.init(data: .url(URL(string: "https://images.example.com/video.mp4")!), mediaType: "video/mp4"))], providerOptions: nil),
            .tool(content: [.toolResult(.init(toolCallId: "call", toolName: "read", output: .content(value: [
                .text(text: "Result", providerOptions: nil),
                .file(data: .reference(["custom": "file-2"]), mediaType: "image/png", filename: nil, providerOptions: nil)
            ])))], providerOptions: nil)
        ]
        _ = try await model.doGenerate(options: .init(prompt: messages, stopSequences: [], reasoning: .some(.none)))
        let request = try #require(await capture.value())
        let body = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
        guard case .object(let object) = body else { Issue.record("Expected JSON request"); return }
        #expect(object["reasoning_effort"] == "none")
        #expect(object["stop"] == [])
        #expect(object["messages"] == [
            ["role": "user", "content": [["type": "file", "file": ["file_id": "file-1"]], ["type": "video_url", "video_url": ["url": "https://images.example.com/video.mp4"]]]],
            ["role": "tool", "tool_call_id": "call", "content": [["type": "text", "text": "Result"], ["type": "file", "file": ["file_id": "file-2"]]]]
        ])
    }
}
