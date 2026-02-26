import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import AlibabaProvider

@Suite("AlibabaProvider")
struct AlibabaProviderTests {
    private let prompt: LanguageModelV3Prompt = [
        .user(content: [.text(LanguageModelV3TextPart(text: "Hello"))], providerOptions: nil)
    ]

    private func httpResponse(url: URL, statusCode: Int = 200, headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: headers)!
    }

    private func jsonData(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [])
    }

    private func minimalChatJSONResponse() -> [String: Any] {
        [
            "id": "chatcmpl-test",
            "created": 1_700_000_000,
            "model": "qwen-plus",
            "choices": [
                [
                    "index": 0,
                    "message": [
                        "role": "assistant",
                        "content": "Hello back"
                    ],
                    "finish_reason": "stop"
                ]
            ],
            "usage": [
                "prompt_tokens": 1,
                "completion_tokens": 2,
                "total_tokens": 3,
                "prompt_tokens_details": [
                    "cached_tokens": 0
                ]
            ]
        ]
    }

    private func minimalChatSSE() -> Data {
        let chunks: [String] = [
            #"data: {"id":"chatcmpl-stream-test","created":1700000000,"model":"qwen-plus","choices":[{"index":0,"delta":{"role":"assistant"},"finish_reason":null}]}"# + "\n\n",
            #"data: {"id":"chatcmpl-stream-test","created":1700000000,"model":"qwen-plus","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}"# + "\n\n",
            #"data: {"id":"chatcmpl-stream-test","created":1700000000,"model":"qwen-plus","choices":[],"usage":{"prompt_tokens":1,"completion_tokens":2,"total_tokens":3,"prompt_tokens_details":{"cached_tokens":0}}}"# + "\n\n",
            "data: [DONE]\n\n",
        ]
        return Data(chunks.joined().utf8)
    }

    private struct CapturedRequest: Sendable {
        let url: String
        let headers: [String: String]
        let body: JSONValue?
    }

    private actor Capture {
        private(set) var requests: [CapturedRequest] = []

        func store(_ request: URLRequest) async throws {
            let url = request.url?.absoluteString ?? ""
            let headers = request.allHTTPHeaderFields ?? [:]
            let body: JSONValue?
            if let data = request.httpBody {
                body = try? JSONDecoder().decode(JSONValue.self, from: data)
            } else {
                body = nil
            }
            requests.append(CapturedRequest(url: url, headers: headers, body: body))
        }

        func first() -> CapturedRequest? { requests.first }
        func last() -> CapturedRequest? { requests.last }
    }

    @Test("includeUsage defaults to true (stream_options.include_usage is sent)")
    func includeUsageDefaultsTrue() async throws {
        let capture = Capture()
        let data = minimalChatSSE()

        let fetch: FetchFunction = { request in
            try await capture.store(request)
            return FetchResponse(body: .data(data), urlResponse: self.httpResponse(url: request.url!))
        }

        let provider = createAlibaba(settings: .init(apiKey: "test-key", fetch: fetch))
        let model = provider.chatModel(modelId: .qwenPlus)
        let result = try await model.doStream(options: .init(prompt: prompt))

        for try await _ in result.stream {}

        guard let first = await capture.first() else {
            Issue.record("Missing captured request")
            return
        }

        #expect(first.url == "https://dashscope-intl.aliyuncs.com/compatible-mode/v1/chat/completions")
        guard case let .object(body)? = first.body else {
            Issue.record("Expected JSON object body")
            return
        }
        #expect(body["stream"] == .bool(true))
        guard case let .object(streamOptions)? = body["stream_options"] else {
            Issue.record("Expected stream_options")
            return
        }
        #expect(streamOptions["include_usage"] == .bool(true))
    }

    @Test("includeUsage can be disabled (stream_options omitted)")
    func includeUsageDisabled() async throws {
        let capture = Capture()
        let data = minimalChatSSE()

        let fetch: FetchFunction = { request in
            try await capture.store(request)
            return FetchResponse(body: .data(data), urlResponse: self.httpResponse(url: request.url!))
        }

        let provider = createAlibaba(settings: .init(apiKey: "test-key", fetch: fetch, includeUsage: false))
        let model = provider.chatModel(modelId: .qwenPlus)
        let result = try await model.doStream(options: .init(prompt: prompt))

        for try await _ in result.stream {}

        guard let first = await capture.first(), case let .object(body)? = first.body else {
            Issue.record("Missing captured request/body")
            return
        }

        #expect(body["stream_options"] == nil)
    }

    @Test("baseURL can be customized for chat API")
    func customBaseURLChat() async throws {
        let capture = Capture()
        let responseJSON = minimalChatJSONResponse()
        let data = try jsonData(responseJSON)

        let fetch: FetchFunction = { request in
            try await capture.store(request)
            return FetchResponse(body: .data(data), urlResponse: self.httpResponse(url: request.url!))
        }

        let provider = createAlibaba(settings: .init(baseURL: "https://custom.example.com/v1", apiKey: "test-key", fetch: fetch))
        let model = provider.chatModel(modelId: AlibabaChatModelId.qwenPlus)
        _ = try await model.doGenerate(options: .init(prompt: prompt))

        guard let first = await capture.first() else {
            Issue.record("Missing captured request")
            return
        }
        #expect(first.url == "https://custom.example.com/v1/chat/completions")
    }

    @Test("videoBaseURL defaults and can be customized")
    func videoBaseURLDefaultAndCustom() async throws {
        func run(base: String?, expectedPrefix: String) async throws {
            let capture = Capture()

            let createTask: [String: Any] = [
                "output": ["task_status": "PENDING", "task_id": "task-abc-123"],
                "request_id": "req-001",
            ]
            let succeeded: [String: Any] = [
                "output": ["task_id": "task-abc-123", "task_status": "SUCCEEDED", "video_url": "https://example.com/out.mp4"],
                "request_id": "req-002",
            ]

            // Pre-serialize payloads to keep the @Sendable fetch closure captures Sendable.
            let createTaskData = try jsonData(createTask)
            let succeededData = try jsonData(succeeded)

            let fetch: FetchFunction = { request in
                try await capture.store(request)
                let url = request.url!.absoluteString
                if url.hasSuffix("/api/v1/services/aigc/video-generation/video-synthesis") {
                    return FetchResponse(body: .data(createTaskData), urlResponse: self.httpResponse(url: request.url!))
                }
                if url.contains("/api/v1/tasks/") {
                    return FetchResponse(body: .data(succeededData), urlResponse: self.httpResponse(url: request.url!))
                }
                throw TestError(message: "Unexpected URL: \(url)")
            }

            let provider = createAlibaba(settings: .init(videoBaseURL: base, apiKey: "test-key", fetch: fetch))
            let model = provider.video(modelId: AlibabaVideoModelId.wan26T2v)
            let providerOptions: SharedV3ProviderOptions = [
                "alibaba": ["pollIntervalMs": .number(1), "pollTimeoutMs": .number(1_000)]
            ]
            _ = try await model.doGenerate(options: .init(
                prompt: "p",
                n: 1,
                providerOptions: providerOptions
            ))

            guard let first = await capture.first() else {
                Issue.record("Missing captured request")
                return
            }
            #expect(first.url.hasPrefix(expectedPrefix))
        }

        try await run(base: nil, expectedPrefix: "https://dashscope-intl.aliyuncs.com")
        try await run(base: "https://dashscope.aliyuncs.com", expectedPrefix: "https://dashscope.aliyuncs.com")
    }

    @Test("unsupported model types throw NoSuchModelError")
    func unsupportedModelTypes() throws {
        let provider = createAlibaba(settings: .init(apiKey: "test-key"))

        #expect(throws: NoSuchModelError.self) {
            _ = try provider.imageModel(modelId: "image-1")
        }
        #expect(throws: NoSuchModelError.self) {
            _ = try provider.textEmbeddingModel(modelId: "embed-1")
        }
    }

    private struct TestError: Error, CustomStringConvertible {
        let message: String
        var description: String { message }
    }
}
