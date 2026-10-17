import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import OpenAIProvider

@Suite("OpenAI image options")
struct OpenAIImageOptionsTests {
    @Test("new quality values reach generation and edit requests", arguments: ["xhigh", "max"])
    func quality(_ quality: String) async throws {
        let model = try createOpenAIProvider(settings: .init(apiKey: "key", fetch: { request in
            if request.url?.path.hasSuffix("/edits") == true {
                let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
                #expect(body.contains("name=\"quality\"\r\n\r\n\(quality)\r\n"))
            } else {
                let body = try JSONDecoder().decode([String: JSONValue].self, from: #require(request.httpBody))
                #expect(body["quality"] == .string(quality))
            }
            return FetchResponse(body: .data(Data(#"{"data":[{"b64_json":"image"}]}"#.utf8)),
                urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"])!)
        })).image("gpt-image-2.5-flare")
        let inputs: [[ImageModelV4File]?] = [nil, []]
        for files in inputs {
            let result = try await model.doGenerate(options: .init(n: 1, files: files,
                providerOptions: ["openai": ["quality": .string(quality)]]))
            #expect(result.images == .base64(["image"]))
        }
    }

    @Test("invalid compression is rejected at the public model boundary", arguments: [
        JSONValue.number(80.5), .number(-1), .number(101), .number(.infinity), .null
    ])
    func compression(_ value: JSONValue) async throws {
        let model = try createOpenAIProvider(settings: .init(apiKey: "key", fetch: { _ in
            Issue.record("Invalid options must not send HTTP")
            throw CancellationError()
        })).image("gpt-image-1")
        let error = await #expect(throws: InvalidArgumentError.self) {
            try await model.doGenerate(options: .init(n: 1, providerOptions: ["openai": ["outputCompression": value]]))
        }
        #expect(error?.argument == "providerOptions")
    }
}
