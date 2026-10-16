import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import DeepSeekProvider

@Suite("DeepSeek stream and files")
struct DeepSeekStreamAndFilesTests {
    @Test func streamPreservesCacheMetadataAcrossUsageOnlyChunks() async throws {
        let chunks: [JSONValue] = [
            ["id": "response", "choices": [["index": 0, "delta": ["role": "assistant", "reasoning_content": "Reason"]]]],
            ["choices": [["delta": ["content": "Answer"], "finish_reason": "stop"]]],
            ["choices": [], "usage": ["prompt_tokens": 10, "completion_tokens": 4, "prompt_cache_miss_tokens": 6, "custom": 12]]
        ]
        let events = try chunks.map { "data: " + String(decoding: try JSONEncoder().encode($0), as: UTF8.self) + "\n\n" }.joined() + "data: [DONE]\n\n"
        let data = Data(events.utf8)
        let fetch: FetchFunction = { request in
            FetchResponse(body: .data(data), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!)
        }
        let model = createDeepSeek(settings: .init(apiKey: "key", fetch: fetch))("deepseek-v4-flash")
        let result = try await model.doStream(options: .init(prompt: DeepSeekProviderTests.prompt))
        var eventsRead: [String] = []
        for try await part in result.stream {
            switch part {
            case .reasoningStart: eventsRead.append("reasoning-start")
            case .reasoningDelta: eventsRead.append("reasoning-delta")
            case .textStart: eventsRead.append("text-start")
            case .reasoningEnd: eventsRead.append("reasoning-end")
            case .textDelta: eventsRead.append("text-delta")
            case .textEnd: eventsRead.append("text-end")
            case .finish(let finish, let usage, let metadata):
                #expect(finish.unified == .stop)
                #expect(usage.inputTokens.total == 10)
                #expect(metadata?["deepseek"] == ["choiceIndex": 0, "messageRole": "assistant", "promptCacheMissTokens": 6])
                #expect(usage.raw == DeepSeekProviderTests.object(chunks[2])["usage"])
                _ = try JSONEncoder().encode(metadata)
            case .error(let error): Issue.record("Unexpected stream error: \(error)")
            default: break
            }
        }
        #expect(eventsRead == ["reasoning-start", "reasoning-delta", "text-start", "reasoning-end", "text-delta", "text-end"])
    }

    @Test func quotaStreamErrorsAreTypedAndNotRetryable() async throws {
        let data = Data("data: {\"error\":{\"message\":\"Quota\",\"code\":\"insufficient_quota\"}}\n\ndata: [DONE]\n\n".utf8)
        let fetch: FetchFunction = { request in
            FetchResponse(body: .data(data), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!)
        }
        let result = try await createDeepSeek(settings: .init(apiKey: "key", fetch: fetch))("deepseek-v4-pro").doStream(options: .init(prompt: DeepSeekProviderTests.prompt))
        var errors: [ProviderStreamError] = []
        for try await part in result.stream {
            if case .error(.providerStreamError(let error)) = part { errors.append(error) }
        }
        #expect(errors.count == 1)
        #expect(errors.first?.statusCode == 429)
        #expect(errors.first?.isRetryable == false)
    }

    @Test func uploadReturnsProviderReferenceAndSendsExpiry() async throws {
        let capture = DeepSeekProviderTests.Capture()
        let response: JSONValue = ["id": "file-1", "object": "file", "filename": "server.png", "purpose": "user_data", "bytes": 3]
        let provider = createDeepSeek(settings: .init(apiKey: "key", fetch: try DeepSeekProviderTests.fetch(response, capture: capture)))
        let result = try await provider.files().uploadFile(options: .init(data: .data(Data([1, 2, 3])), mediaType: "image/png", filename: "image.png", providerOptions: ["deepseek": ["expiresAfter": 3600]]))
        #expect(result.providerReference == ["deepseek": "file-1"])
        #expect(result.filename == "server.png")
        #expect(result.providerMetadata?["deepseek"]?["bytes"] == 3)
        let request = try #require(await capture.value())
        #expect(request.url?.path == "/files")
        let form = String(decoding: try #require(request.httpBody), as: UTF8.self)
        #expect(form.contains("name=\"expires_after[seconds]\"\r\n\r\n3600"))
        #expect(form.contains("name=\"purpose\"\r\n\r\nuser_data"))
    }
}
