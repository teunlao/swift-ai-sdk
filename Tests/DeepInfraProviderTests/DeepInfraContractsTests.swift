import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import DeepInfraProvider

@Suite("DeepInfra native contracts")
struct DeepInfraContractsTests {
    @Test func reasoningUsageIsCorrectedWhenCompletionCountIsMissing() async throws {
        let data = Data(#"{"choices":[{"message":{"content":"Answer"},"finish_reason":"stop"}],"usage":{"prompt_tokens":2,"total_tokens":2,"completion_tokens_details":{"reasoning_tokens":5},"custom":9}}"#.utf8)
        let fetch: FetchFunction = { request in FetchResponse(body: .data(data), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!) }
        let result = try await createDeepInfra(settings: .init(apiKey: "key", fetch: fetch))("gemini").doGenerate(options: .init(prompt: [], responseFormat: .json(schema: ["type": "object"], name: nil, description: nil)))
        #expect(result.usage.outputTokens.total == 5)
        #expect(result.usage.outputTokens.reasoning == 5)
        #expect(result.usage.outputTokens.text == 0)
        guard case .object(let usage)? = result.usage.raw else { Issue.record("Expected raw usage"); return }
        #expect(usage["completion_tokens"] == 5)
        #expect(usage["total_tokens"] == 7)
        #expect(usage["custom"] == 9)
        #expect(result.warnings.isEmpty)
    }

    @Test func imageEditsMergeOverridesAndKeepUnbracketedMultipartValues() async throws {
        let fetch: FetchFunction = { request in
            let form = String(decoding: try #require(request.httpBody), as: UTF8.self)
            #expect(request.url?.absoluteString == "https://api.deepinfra.com/v1/openai/images/edits")
            #expect(form.components(separatedBy: "name=\"n\"").count - 1 == 1)
            #expect(form.contains("name=\"n\"\r\n\r\n3\r\n"))
            #expect(form.contains("name=\"tags\"\r\n\r\nnull\r\n"))
            #expect(form.contains("name=\"tags\"\r\n\r\n[object Object]\r\n"))
            #expect(form.contains("name=\"image\"; filename=\"blob\""))
            return FetchResponse(body: .data(Data(#"{"data":[{"b64_json":"result"}]}"#.utf8)), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
        }
        let model = try createDeepInfra(settings: .init(apiKey: "key", fetch: fetch)).imageModel(modelId: "Qwen/Qwen-Image-Edit")
        #expect(try await model.supportsFileInputs == true)
        #expect(try await model.supportsMaskInputs == true)
        let result = try await model.doGenerate(options: .init(prompt: "Edit", n: 1, files: [.url(url: "data:image/png;base64,AQI=", providerOptions: nil)],
                                                              providerOptions: ["deepinfra": ["n": 3, "tags": [1, .null, ["key": "value"]]]]))
        #expect(result.images == .base64(["result"]))
    }
    @Test(arguments: [false, true])
    func imageResponseFormatIsValidatedBeforeTransport(editing: Bool) async throws {
        let model = try createDeepInfra(settings: .init(apiKey: "key", fetch: { _ in throw CancellationError() })).imageModel(modelId: "image")
        await #expect(throws: InvalidArgumentError.self) {
            _ = try await model.doGenerate(options: .init(prompt: "Image", n: 1, files: editing ? [.file(mediaType: "image/png", data: .binary(Data([1])), providerOptions: nil)] : nil,
                                                         providerOptions: ["deepinfra": ["response_format": "url"]]))
        }
    }
}
