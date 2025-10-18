import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import SwiftAISDK

private let completionPrompt: LanguageModelV3Prompt = [
    .user(
        content: [
            .text(LanguageModelV3TextPart(text: "Hello"))
        ],
        providerOptions: nil
    )
]

@Suite("OpenAICompletionLanguageModel")
struct OpenAICompletionLanguageModelTests {
    private func makeConfig(fetch: @escaping FetchFunction) -> OpenAIConfig {
        OpenAIConfig(
            provider: "openai.completion",
            url: { _ in "https://api.openai.com/v1/completions" },
            headers: { ["Authorization": "Bearer test-api-key"] },
            fetch: fetch,
            _internal: .init(currentDate: { Date(timeIntervalSince1970: 1_711_363_706) })
        )
    }

    private func makeLogprobsValue() -> JSONValue {
        .object([
            "tokens": .array([
                .string("Hello"),
                .string(","),
                .string(" World!")
            ]),
            "token_logprobs": .array([
                .number(-0.01),
                .number(-0.02),
                .number(-0.03)
            ]),
            "top_logprobs": .array([
                .object(["Hello": .number(-0.01)]),
                .object([",": .number(-0.02)]),
                .object([" World!": .number(-0.03)])
            ])
        ])
    }

    @Test("doGenerate maps response, usage and request headers")
    func testDoGenerateMapsResponse() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func current() -> URLRequest? { request }
        }

        let capture = RequestCapture()
        let logprobsValue = makeLogprobsValue()

        let responseJSON: [String: Any] = [
            "id": "cmpl-123",
            "created": 1_711_363_706,
            "model": "gpt-3.5-turbo-instruct",
            "choices": [[
                "text": "Hello, World!",
                "index": 0,
                "logprobs": try logprobsValue.asJSONObject(),
                "finish_reason": "stop"
            ]],
            "usage": [
                "prompt_tokens": 4,
                "completion_tokens": 6,
                "total_tokens": 10
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": "application/json",
                "X-Test-Header": "response-value"
            ]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAICompletionLanguageModel(
            modelId: "gpt-3.5-turbo-instruct",
            config: makeConfig(fetch: fetch)
        )

        let options = LanguageModelV3CallOptions(
            prompt: completionPrompt,
            headers: ["Custom-Request": "request-value"],
            providerOptions: [
                "openai": ["logprobs": .number(1)]
            ]
        )

        let result = try await model.doGenerate(options: options)

        #expect(result.content.count == 1)
        if case .text(let text) = result.content.first {
            #expect(text.text == "Hello, World!")
        } else {
            Issue.record("Expected text content")
        }

        #expect(result.finishReason == .stop)
        #expect(result.usage.inputTokens == 4)
        #expect(result.usage.outputTokens == 6)
        #expect(result.usage.totalTokens == 10)

        if let metadata = result.providerMetadata?["openai"] {
            #expect(metadata["logprobs"] == logprobsValue)
        } else {
            Issue.record("Missing provider metadata")
        }

        if let response = result.response {
            #expect(response.id == "cmpl-123")
            #expect(response.modelId == "gpt-3.5-turbo-instruct")
            #expect(response.timestamp == Date(timeIntervalSince1970: 1_711_363_706))
        } else {
            Issue.record("Missing response metadata")
        }

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            Issue.record("Missing captured request")
            return
        }

        let headers = request.allHTTPHeaderFields ?? [:]
        let normalizedHeaders = Dictionary(uniqueKeysWithValues: headers.map { ($0.key.lowercased(), $0.value) })
        #expect(normalizedHeaders["authorization"] == "Bearer test-api-key")
        #expect(normalizedHeaders["custom-request"] == "request-value")
        #expect(normalizedHeaders["content-type"] == "application/json")

        #expect(json["model"] as? String == "gpt-3.5-turbo-instruct")
        #expect((json["prompt"] as? String)?.contains("Hello") == true)
        if let stop = json["stop"] as? [String] {
            #expect(stop.contains("\nuser:"))
        } else {
            Issue.record("Missing stop sequences")
        }
    }

    @Test("doStream emits deltas, usage and provider metadata")
    func testDoStreamEmitsDeltas() async throws {
        actor RequestBodyCapture {
            var data: Data?
            func store(_ body: Data?) { data = body }
            func current() -> Data? { data }
        }

        let capture = RequestBodyCapture()
        let logprobsValue = makeLogprobsValue()

        func chunk(_ dictionary: [String: Any]) throws -> String {
            let data = try JSONSerialization.data(withJSONObject: dictionary)
            guard let string = String(data: data, encoding: .utf8) else {
                throw UnsupportedFunctionalityError(functionality: "Unable to encode chunk")
            }
            return "data: \(string)\n\n"
        }

        let chunks: [String] = [
            try chunk([
                "id": "cmpl-chunk-1",
                "object": "text_completion",
                "created": 1_711_363_706,
                "model": "gpt-3.5-turbo-instruct",
                "choices": [[
                    "text": "Hello",
                    "index": 0,
                    "logprobs": try logprobsValue.asJSONObject(),
                    "finish_reason": NSNull()
                ]]
            ]),
            try chunk([
                "id": "cmpl-final",
                "object": "text_completion",
                "created": 1_711_363_708,
                "model": "gpt-3.5-turbo-instruct",
                "choices": [[
                    "text": " World!",
                    "index": 0,
                    "logprobs": try logprobsValue.asJSONObject(),
                    "finish_reason": "stop"
                ]]
            ]),
            try chunk([
                "id": "cmpl-final",
                "object": "text_completion",
                "created": 1_711_363_708,
                "model": "gpt-3.5-turbo-instruct",
                "usage": [
                    "prompt_tokens": 5,
                    "completion_tokens": 7,
                    "total_tokens": 12
                ],
                "choices": []
            ]),
            "data: [DONE]\n\n"
        ]

        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": "text/event-stream",
                "Cache-Control": "no-cache"
            ]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request.httpBody)
            let stream = AsyncThrowingStream<Data, Error> { continuation in
                for entry in chunks {
                    continuation.yield(Data(entry.utf8))
                }
                continuation.finish()
            }
            return FetchResponse(body: .stream(stream), urlResponse: httpResponse)
        }

        let model = OpenAICompletionLanguageModel(
            modelId: "gpt-3.5-turbo-instruct",
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doStream(
            options: LanguageModelV3CallOptions(
                prompt: completionPrompt,
                includeRawChunks: false,
                providerOptions: [
                    "openai": ["logprobs": .bool(true)]
                ]
            )
        )

        var parts: [LanguageModelV3StreamPart] = []
        for try await part in result.stream {
            parts.append(part)
        }

        #expect(parts.count >= 6)
        if parts.count >= 1 {
            if case .streamStart(let warnings) = parts[0] {
                #expect(warnings.isEmpty)
            } else {
                Issue.record("Expected stream-start part")
            }
        }

        if parts.count >= 2 {
            if case .responseMetadata(let id, let modelId, let timestamp) = parts[1] {
                #expect(id == "cmpl-chunk-1")
                #expect(modelId == "gpt-3.5-turbo-instruct")
                #expect(timestamp == Date(timeIntervalSince1970: 1_711_363_706))
            } else {
                Issue.record("Expected response-metadata part")
            }
        }

        if let last = parts.last {
            if case .finish(let finishReason, let usage, let metadata) = last {
                #expect(finishReason == .stop)
                #expect(usage.inputTokens == 5)
                #expect(usage.outputTokens == 7)
                #expect(usage.totalTokens == 12)
                if let openaiMetadata = metadata?["openai"] {
                    #expect(openaiMetadata["logprobs"] == logprobsValue)
                } else {
                    Issue.record("Missing provider metadata in finish")
                }
            } else {
                Issue.record("Expected finish part")
            }
        }

        guard let body = await capture.current(),
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            Issue.record("Missing captured stream request")
            return
        }

        #expect(json["stream"] as? Bool == true)
        if let streamOptions = json["stream_options"] as? [String: Any] {
            #expect(streamOptions["include_usage"] as? Bool == true)
        } else {
            Issue.record("Missing stream_options")
        }
    }

    @Test("doStream handles error chunks")
    func testDoStreamHandlesErrorChunk() async throws {
        let errorChunk: String = {
            let value: [String: Any] = [
                "error": [
                    "message": "Server error",
                    "type": "server_error",
                    "param": NSNull(),
                    "code": NSNull()
                ]
            ]
            let data = try! JSONSerialization.data(withJSONObject: value)
            return "data: \(String(data: data, encoding: .utf8)!)\n\n"
        }()

        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!

        let fetch: FetchFunction = { _ in
            let stream = AsyncThrowingStream<Data, Error> { continuation in
                continuation.yield(Data(errorChunk.utf8))
                continuation.yield(Data("data: [DONE]\n\n".utf8))
                continuation.finish()
            }
            return FetchResponse(body: .stream(stream), urlResponse: httpResponse)
        }

        let model = OpenAICompletionLanguageModel(
            modelId: "gpt-3.5-turbo-instruct",
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doStream(
            options: LanguageModelV3CallOptions(
                prompt: completionPrompt,
                includeRawChunks: false
            )
        )

        var parts: [LanguageModelV3StreamPart] = []
        for try await part in result.stream {
            parts.append(part)
        }

        #expect(parts.count == 3)
        if parts.count == 3 {
            if case .streamStart = parts[0] {
                // expected
            } else {
                Issue.record("Expected stream-start")
            }

            if case .error(let errorValue) = parts[1] {
                switch errorValue {
                case .object(let obj):
                    if case .object(let nested)? = obj["error"] {
                        #expect(nested["type"] == .string("server_error"))
                    } else {
                        Issue.record("Unexpected error structure")
                    }
                case .string(let message):
                    #expect(message.contains("Server error"))
                default:
                    Issue.record("Unexpected error payload")
                }
            } else {
                Issue.record("Expected error part")
            }

            if case .finish(let finishReason, _, _) = parts[2] {
                #expect(finishReason == .error)
            } else {
                Issue.record("Expected finish part")
            }
        }
    }
}

private extension JSONValue {
    func asJSONObject() throws -> Any {
        switch self {
        case .null:
            return NSNull()
        case .bool(let value):
            return value
        case .number(let value):
            return value
        case .string(let value):
            return value
        case .array(let array):
            return try array.map { try $0.asJSONObject() }
        case .object(let object):
            return try object.mapValues { try $0.asJSONObject() }
        }
    }
}
