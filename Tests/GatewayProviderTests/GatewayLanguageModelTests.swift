import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
@testable import GatewayProvider

@Suite("GatewayLanguageModel")
struct GatewayLanguageModelTests {
    actor RequestCapture {
        private(set) var request: URLRequest?
        func store(_ request: URLRequest) { self.request = request }
        func current() -> URLRequest? { request }
    }

    private func normalizedHeaders(_ request: URLRequest) -> [String: String] {
        (request.allHTTPHeaderFields ?? [:]).reduce(into: [String: String]()) { result, pair in
            let key = pair.key.lowercased()
            if key == "user-agent" { return }
            result[key] = pair.value
        }
    }

    private func httpResponse(for request: URLRequest, statusCode: Int = 200, headers: [String: String] = [:]) throws -> HTTPURLResponse {
        let url = try #require(request.url)
        return try #require(HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        ))
    }

    private func makeModel(
        fetch: @escaping FetchFunction,
        o11yHeaders: [String: String] = [:]
    ) -> GatewayLanguageModel {
        GatewayLanguageModel(
            modelId: GatewayModelId(rawValue: "test-model"),
            config: GatewayLanguageModelConfig(
                provider: "test-provider",
                baseURL: "https://api.test.com",
                headers: { () async throws -> [String: String?] in
                    [
                        "Authorization": "Bearer test-token",
                        GATEWAY_AUTH_METHOD_HEADER: "api-key",
                    ]
                },
                fetch: fetch,
                o11yHeaders: { () async throws -> [String: String?] in
                    o11yHeaders.mapValues { Optional($0) }
                }
            )
        )
    }

    @Test("retryable failures after HTTP success retain their retry metadata")
    func retryableSuccessfulStatusFailure() async throws {
        let model = makeModel(fetch: { _ in
            throw APICallError(
                message: "response ended early", url: "https://api.test.com/language-model",
                requestBodyValues: nil, statusCode: 200, responseBody: "{}", isRetryable: true
            )
        })
        do {
            _ = try await model.doGenerate(options: .init(prompt: []))
            Issue.record("Expected response error")
        } catch let error as GatewayResponseError {
            #expect(error.statusCode == 200)
            #expect(error.isRetryable)
        }
    }

    @Test("public error messages preserve the server reason and generation id")
    func publicErrorMessage() async throws {
        let provider = createGateway(settings: .init(apiKey: "key", fetch: { request in
            FetchResponse(
                body: .data(Data(#"{"error":{"message":"Request quota exhausted","type":"rate_limit_exceeded"},"generationId":"gen_quota"}"#.utf8)),
                urlResponse: try httpResponse(for: request, statusCode: 429, headers: ["Content-Type": "application/json"])
            )
        }))
        let model = try provider.languageModel(modelId: "test-model")
        do {
            _ = try await model.doGenerate(options: .init(prompt: []))
            Issue.record("Expected rate limit error")
        } catch let error as GatewayRateLimitError {
            #expect(error.generationId == "gen_quota")
            #expect(AISDKProvider.getErrorMessage(error).contains("Request quota exhausted"))
            #expect(AISDKProvider.getErrorMessage(error).contains("gen_quota"))
            #expect(error.localizedDescription.contains("Request quota exhausted"))
            #expect(error.localizedDescription.contains("gen_quota"))
        }
    }

    @Test("doGenerate passes headers, strips abortSignal, and maps response")
    func doGenerateRequestAndResponseMapping() async throws {
        let capture = RequestCapture()

        let responseBody: [String: Any] = [
            "id": "test-id",
            "created": 1_711_115_037,
            "model": "test-model",
            "content": [["type": "text", "text": "Hello, World!"]],
            "finishReason": ["unified": "stop", "raw": "stop"],
            "usage": [
                "inputTokens": ["total": 4, "noCache": 4],
                "outputTokens": ["total": 30, "text": 30],
            ],
            "warnings": [["type": "compatibility", "feature": "reasoning", "details": "provider default"]],
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseBody, options: [.sortedKeys])

        let fetch: FetchFunction = { request in
            await capture.store(request)
            let httpResponse = try httpResponse(for: request, headers: ["Content-Type": "application/json"])
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let o11yHeaders: [String: String] = [
            "ai-o11y-deployment-id": "test-deployment",
            "ai-o11y-environment": "production",
            "ai-o11y-region": "iad1",
        ]

        let model = makeModel(fetch: fetch, o11yHeaders: o11yHeaders)

        let controller = AbortController()

        let prompt: LanguageModelV4Prompt = [
            .user(content: [.text(LanguageModelV4TextPart(text: "Hello"))], providerOptions: nil)
        ]

        let result = try await model.doGenerate(options: .init(
            prompt: prompt,
            abortSignal: { controller.isCancelled },
            headers: ["Custom-Header": "test-value"],
            reasoning: .high
        ))

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            Issue.record("Missing request capture")
            return
        }

        #expect(request.url?.absoluteString == "https://api.test.com/language-model")

        let headers = normalizedHeaders(request)
        #expect(headers["authorization"] == "Bearer test-token")
        #expect(headers["custom-header"] == "test-value")
        #expect(headers["ai-language-model-specification-version"] == "4")
        #expect(headers["ai-language-model-id"] == "test-model")
        #expect(headers["ai-language-model-streaming"] == "false")
        for (key, value) in o11yHeaders {
            #expect(headers[key] == value)
        }

        #expect(json["abortSignal"] == nil)
        #expect(json["reasoning"] as? String == "high")

        #expect(result.content.count == 1)
        if case .text(let text) = result.content.first {
            #expect(text.text == "Hello, World!")
        } else {
            Issue.record("Expected text content")
        }

        #expect(result.warnings == [.compatibility(feature: "reasoning", details: "provider default")])
        #expect(result.finishReason.unified == .stop)
        #expect(result.finishReason.raw == "stop")
        #expect(result.usage.inputTokens.total == 4)
        #expect(result.usage.inputTokens.noCache == 4)
        #expect(result.usage.outputTokens.total == 30)
        #expect(result.usage.outputTokens.text == 30)
    }

    @Test("doGenerate encodes binary file parts as tagged base64 data")
    func doGenerateEncodesFileParts() async throws {
        let capture = RequestCapture()

        let responseBody: [String: Any] = [
            "content": [["type": "text", "text": "ok"]],
            "finishReason": ["unified": "stop"],
            "usage": ["inputTokens": ["total": 1], "outputTokens": ["total": 1]],
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responseBody, options: [.sortedKeys])

        let fetch: FetchFunction = { request in
            await capture.store(request)
            let httpResponse = try httpResponse(for: request, headers: ["Content-Type": "application/json"])
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = makeModel(fetch: fetch)

        let bytes = Data([1, 2, 3, 4])
        let expectedBase64 = bytes.base64EncodedString()

        let prompt: LanguageModelV4Prompt = [
            .user(
                content: [
                    .text(LanguageModelV4TextPart(text: "Describe:")),
                    .file(LanguageModelV4FilePart(data: .data(bytes), mediaType: "image/jpeg")),
                ],
                providerOptions: nil
            ),
            .assistant(content: [.reasoningFile(.init(data: .data(bytes), mediaType: "application/octet-stream"))], providerOptions: nil),
            .tool(content: [.toolResult(.init(toolCallId: "call-1", toolName: "read", output: .content(value: [
                .file(data: .data(bytes), mediaType: "image/png", filename: "result.png", providerOptions: nil)
            ])))], providerOptions: nil)
        ]

        _ = try await model.doGenerate(options: .init(prompt: prompt))

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any],
              let promptArray = json["prompt"] as? [[String: Any]],
              let first = promptArray.first,
              let content = first["content"] as? [[String: Any]],
              content.count == 2
        else {
            Issue.record("Expected prompt content in request body")
            return
        }

        let file = content[1]
        #expect(file["type"] as? String == "file")
        #expect(file["mediaType"] as? String == "image/jpeg")
        let data = try #require(file["data"] as? [String: String])
        #expect(data == ["type": "data", "data": expectedBase64])
        let reasoning = try #require((promptArray[1]["content"] as? [[String: Any]])?.first)
        #expect(reasoning["data"] as? [String: String] == data)
        let toolResult = try #require((promptArray[2]["content"] as? [[String: Any]])?.first)
        let output = try #require(toolResult["output"] as? [String: Any])
        let nested = try #require((output["value"] as? [[String: Any]])?.first)
        #expect(nested["data"] as? [String: String] == data)
        #expect(nested["filename"] as? String == "result.png")
    }

    @Test("doStream filters gateway raw chunks based on includeRawChunks")
    func doStreamFiltersRawChunks() async throws {
        let capture = RequestCapture()

        let sseChunks: [String] = [
            #"data: {"type":"stream-start","warnings":[]}"# + "\n\n",
            #"data: {"type":"raw","rawValue":{"id":"test-chunk","object":"chat.completion.chunk"}}"# + "\n\n",
            #"data: {"type":"text-delta","id":"text","delta":"Hello"}"# + "\n\n",
            #"data: {"type":"raw","rawValue":{"id":"test-chunk-2","object":"chat.completion.chunk"}}"# + "\n\n",
            #"data: {"type":"text-delta","id":"text","delta":" world"}"# + "\n\n",
            #"data: {"type":"finish","finishReason":{"unified":"stop"},"usage":{"inputTokens":{"total":10},"outputTokens":{"total":5}}}"# + "\n\n",
        ]

        let sseData = Data(sseChunks.joined().utf8)
        let httpHeaders = ["Content-Type": "text/event-stream"]

        let fetch: FetchFunction = { request in
            await capture.store(request)
            let response = try httpResponse(for: request, headers: httpHeaders)
            return FetchResponse(body: .data(sseData), urlResponse: response)
        }

        let model = makeModel(fetch: fetch)
        let prompt: LanguageModelV4Prompt = [
            .user(content: [.text(LanguageModelV4TextPart(text: "Hello"))], providerOptions: nil)
        ]

        // includeRawChunks = false
        let result = try await model.doStream(options: .init(prompt: prompt, includeRawChunks: false))
        var parts: [LanguageModelV4StreamPart] = []
        for try await part in result.stream {
            parts.append(part)
        }

        #expect(parts.contains(where: { if case .raw = $0 { return true } else { return false } }) == false)
        #expect(parts.contains(where: { if case .streamStart = $0 { return true } else { return false } }) == true)

        let deltas: [String] = parts.compactMap { part in
            if case .textDelta(_, let delta, _) = part { return delta }
            return nil
        }
        #expect(deltas == ["Hello", " world"])

        guard let finish = parts.last(where: { if case .finish = $0 { return true } else { return false } }) else {
            Issue.record("Expected finish chunk")
            return
        }

        if case .finish(let finishReason, let usage, _) = finish {
            #expect(finishReason.unified == .stop)
            #expect(usage.inputTokens.total == 10)
            #expect(usage.outputTokens.total == 5)
        }

        // includeRawChunks = true
        let resultRaw = try await model.doStream(options: .init(prompt: prompt, includeRawChunks: true))
        var partsRaw: [LanguageModelV4StreamPart] = []
        for try await part in resultRaw.stream {
            partsRaw.append(part)
        }

        #expect(partsRaw.contains(where: { if case .raw = $0 { return true } else { return false } }) == true)
    }

    @Test("stream demand paces HTTP reads and cancellation releases a pending body read", .timeLimit(.minutes(1)))
    func streamFlowControl() async throws {
        let bytes = AsyncThrowingStream<Data, Error>.makeStream()
        let cancelled = AsyncStream<Void>.makeStream()
        bytes.continuation.onTermination = { reason in
            if case .cancelled = reason { cancelled.continuation.yield(()) }
        }
        defer { bytes.continuation.finish(); cancelled.continuation.finish() }
        bytes.continuation.yield(Data(#"data: {"type":"text-delta","id":"text","delta":"first"}"#.utf8) + Data("\n\n".utf8))
        bytes.continuation.yield(Data(#"data: {"type":"text-delta","id":"text","delta":"second"}"#.utf8) + Data("\n\n".utf8))
        let source = BodyReader(bytes.stream)
        let provider = createGateway(settings: .init(apiKey: "key", fetch: { request in
            FetchResponse(
                body: .stream(AsyncThrowingStream { try await source.next() }),
                urlResponse: try httpResponse(for: request, headers: ["Content-Type": "text/event-stream"])
            )
        }))
        let model = try provider.languageModel(modelId: "test-model")
        let result = try await model.doStream(options: .init(prompt: []))
        var iterator = result.stream.makeAsyncIterator()
        #expect(try await iterator.next() == .textDelta(id: "text", delta: "first", providerMetadata: nil))
        let readAhead = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                var reads = source.readAhead.stream.makeAsyncIterator()
                return await reads.next() != nil
            }
            group.addTask {
                try? await Task.sleep(for: .milliseconds(50))
                return false
            }
            defer { group.cancelAll() }
            return await group.next() ?? false
        }
        #expect(readAhead == false)
        #expect(try await iterator.next() == .textDelta(id: "text", delta: "second", providerMetadata: nil))
        let consumer = Task {
            var remainder = result.stream.makeAsyncIterator()
            return try await remainder.next()
        }
        defer { consumer.cancel() }
        var pending = source.pending.stream.makeAsyncIterator()
        _ = await pending.next()
        consumer.cancel()
        _ = try? await consumer.value
        var endings = cancelled.stream.makeAsyncIterator()
        #expect(await endings.next() != nil)
    }

    private final class BodyReader: @unchecked Sendable {
        private var iterator: AsyncThrowingStream<Data, Error>.Iterator
        private var pulls = 0
        let readAhead = AsyncStream<Void>.makeStream()
        let pending = AsyncStream<Void>.makeStream()

        init(_ stream: AsyncThrowingStream<Data, Error>) { iterator = stream.makeAsyncIterator() }

        func next() async throws -> Data? {
            pulls += 1
            if pulls == 2 { readAhead.continuation.yield(()) }
            if pulls == 3 { pending.continuation.yield(()) }
            return try await iterator.next()
        }
    }

    @Test("doStream converts response-metadata timestamp strings to Date")
    func doStreamConvertsResponseMetadataTimestamp() async throws {
        let timestampString = "2023-12-07T10:30:00.000Z"

        let sseChunks: [String] = [
            #"data: {"type":"stream-start","warnings":[]}"# + "\n\n",
            #"data: {"type":"response-metadata","id":"test-id","modelId":"test-model","timestamp":"\#(timestampString)"}"# + "\n\n",
            #"data: {"type":"finish","finishReason":{"unified":"stop"},"usage":{"inputTokens":{"total":1},"outputTokens":{"total":1}}}"# + "\n\n",
        ]
        let sseData = Data(sseChunks.joined().utf8)

        let fetch: FetchFunction = { request in
            let response = try httpResponse(for: request, headers: ["Content-Type": "text/event-stream"])
            return FetchResponse(body: .data(sseData), urlResponse: response)
        }

        let model = makeModel(fetch: fetch)
        let prompt: LanguageModelV4Prompt = [
            .user(content: [.text(LanguageModelV4TextPart(text: "Hello"))], providerOptions: nil)
        ]

        let result = try await model.doStream(options: .init(prompt: prompt, includeRawChunks: false))
        var responseMetadata: LanguageModelV4StreamPart?
        for try await part in result.stream {
            if case .responseMetadata = part {
                responseMetadata = part
            }
        }

        guard let responseMetadata else {
            Issue.record("Expected response-metadata chunk")
            return
        }

        if case .responseMetadata(let id, let modelId, let timestamp) = responseMetadata {
            #expect(id == "test-id")
            #expect(modelId == "test-model")
            guard let timestamp else {
                Issue.record("Expected timestamp date")
                return
            }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            #expect(formatter.string(from: timestamp) == timestampString)
        }
    }
}

private final class AbortController: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var isCancelled: Bool = false
    func cancel() {
        lock.lock()
        isCancelled = true
        lock.unlock()
    }
}
