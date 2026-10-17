import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import CohereProvider

@Suite("Cohere prompt HTTP boundaries")
struct ConvertToCohereChatPromptTests {
    private func requestBody(_ prompt: LanguageModelV4Prompt) async throws -> JSONObject {
        let recorder = RequestRecorder()
        let provider = createCohere(settings: .init(apiKey: "key", fetch: { request in
            await recorder.record(request)
            return FetchResponse(body: .data(Data(#"{"message":{"role":"assistant","content":[]},"finish_reason":"COMPLETE","usage":{"tokens":{"input_tokens":0,"output_tokens":0}}}"#.utf8)), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
        }))
        _ = try await provider.languageModel(.commandAVision072025).doGenerate(options: .init(prompt: prompt))
        let request = try #require(await recorder.first())
        return try JSONDecoder().decode(JSONObject.self, from: #require(request.httpBody))
    }

    @Test("mixed text and image parts retain order, detected media type, and image fidelity")
    func mixedImage() async throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let body = try await requestBody([.user(content: [
            .text(.init(text: "Before")), .text(.init(text: "")),
            .file(.init(data: .data(png), mediaType: "image", providerOptions: ["cohere": ["detail": "high"]])),
            .text(.init(text: "After")), .text(.init(text: "More")),
            .file(.init(data: .data(Data("PDF-like text".utf8)), mediaType: "application/pdf", filename: "document.pdf"))
        ], providerOptions: nil)])
        #expect(body["messages"] == [["role": "user", "content": [
            ["type": "text", "text": "Before"],
            ["type": "image_url", "image_url": ["url": "data:image/png;base64,iVBORw0KGgo=", "detail": "high"]],
            ["type": "text", "text": "After"], ["type": "text", "text": "More"]
        ]]])
        #expect(body["documents"] == [["data": ["text": "PDF-like text", "title": "document.pdf"]]])
    }

    @Test("base64 and remote images become image URLs rather than documents", arguments: [false, true])
    func imageVariants(remote: Bool) async throws {
        let data: SharedV4FileData = remote ? .url(URL(string: "https://example.com/image.png")!) : .base64("AAECAw==")
        let body = try await requestBody([.user(content: [.file(.init(data: data, mediaType: "image/png"))], providerOptions: nil)])
        let url = remote ? "https://example.com/image.png" : "data:image/png;base64,AAECAw=="
        #expect(body["messages"] == [["role": "user", "content": [["type": "image_url", "image_url": ["url": .string(url)]]]]])
        #expect(body["documents"] == nil)
    }

    @Test("non-image files preserve source string semantics and text-only parts join without separators")
    func documents() async throws {
        let bytes = Data([0xEF, 0xBB, 0xBF, 0xFF])
        let body = try await requestBody([.user(content: [
            .text(.init(text: "One")), .text(.init(text: "Two")),
            .file(.init(data: .text("Inline text"), mediaType: "text")),
            .file(.init(data: .base64("RmlsZQ=="), mediaType: "application/octet-stream", filename: "raw.txt")),
            .file(.init(data: .data(bytes), mediaType: "application/pdf"))
        ], providerOptions: nil)])
        #expect(body["messages"] == [["role": "user", "content": "OneTwo"]])
        #expect(body["documents"] == [
            ["data": ["text": "Inline text"]], ["data": ["text": "RmlsZQ==", "title": "raw.txt"]],
            ["data": ["text": "\u{FFFD}"]]
        ])
    }

    @Test("unsupported file representations fail through the public model", arguments: ["image-reference", "image-text", "document-reference", "document-url"])
    func unsupportedFiles(kind: String) async throws {
        let image = kind.hasPrefix("image")
        let data: SharedV4FileData
        if kind.hasSuffix("reference") { data = .reference(["cohere": "file-id"]) }
        else if kind.hasSuffix("url") { data = .url(URL(string: "https://example.com/file.txt")!) }
        else { data = .text("Image text") }
        await #expect(throws: UnsupportedFunctionalityError.self) {
            _ = try await requestBody([.user(content: [.file(.init(data: data, mediaType: image ? "image/png" : "text/plain"))], providerOptions: nil)])
        }
    }

    @Test("invalid image detail rejects at the provider-option boundary", arguments: [JSONValue.string("invalid"), .null])
    func invalidImageDetail(detail: JSONValue) async throws {
        await #expect(throws: InvalidArgumentError.self) {
            _ = try await requestBody([.user(content: [.file(.init(data: .base64("AAECAw=="), mediaType: "image/png", providerOptions: ["cohere": ["detail": detail]]))], providerOptions: nil)])
        }
    }

    @Test("assistant calls and tool results replay with native V4 content")
    func replay() async throws {
        let body = try await requestBody([
            .assistant(content: [.text(.init(text: "Calling")), .reasoning(.init(text: "ignored")), .toolCall(.init(toolCallId: "call-1", toolName: "tool", input: ["city": "Paris"]))], providerOptions: nil),
            .tool(content: [
                .toolApprovalResponse(.init(approvalId: "approval", approved: true)),
                .toolResult(.init(toolCallId: "call-1", toolName: "tool", output: .json(value: ["weather": "sunny"]))),
                .toolResult(.init(toolCallId: "call-2", toolName: "tool", output: .executionDenied(reason: nil)))
            ], providerOptions: nil)
        ])
        #expect(body["messages"] == [
            ["role": "assistant", "tool_calls": [["id": "call-1", "type": "function", "function": ["name": "tool", "arguments": #"{"city":"Paris"}"#]]]],
            ["role": "tool", "tool_call_id": "call-1", "content": #"{"weather":"sunny"}"#],
            ["role": "tool", "tool_call_id": "call-2", "content": "Tool call execution denied."]
        ])
    }
}
