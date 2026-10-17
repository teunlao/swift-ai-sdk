import Foundation
import Testing
import AISDKProvider
import OpenResponsesProvider

@Suite("Open Responses history HTTP boundaries")
struct ConvertToOpenResponsesInputTests {
    private let annotation: JSONValue = ["type": "url_citation", "start_index": 0, "end_index": 1, "url": "https://example.com", "title": "Source"]

    @Test("strict history distinguishes easy messages from complete item replay", arguments: [false, true])
    func strictInput(strict: Bool) async throws {
        let endpoint = OpenResponsesTestEndpoint()
        let provider = try openResponsesProvider(endpoint, strict: strict)
        let history: LanguageModelV4Prompt = [
            .system(content: "one", providerOptions: nil), .system(content: "two", providerOptions: nil),
            .assistant(content: [
                .text(.init(text: "easy-")), .text(.init(text: "text")),
                .text(.init(text: "complete", providerOptions: ["acme": ["itemId": "message", "annotations": .array([annotation])]])),
                .toolCall(.init(toolCallId: "call", toolName: "tool", input: .string(#"{"arg":1}"#), providerOptions: ["acme": ["itemId": "function"]])),
                .text(.init(text: "after", providerOptions: ["acme": ["itemId": "next-message"]]))
            ], providerOptions: nil)
        ]
        _ = try await provider("model").doGenerate(options: .init(prompt: history))
        let body = try await endpoint.lastBody()
        #expect(body["instructions"] == "one\ntwo")
        let easy: JSONValue = strict ? ["type": "message", "role": "assistant", "content": "easy-text"] : ["type": "message", "role": "assistant", "content": [["type": "output_text", "text": "easy-"], ["type": "output_text", "text": "text"]]]
        var complete: JSONObject = ["type": "message", "role": "assistant", "id": "message", "content": [["type": "output_text", "text": "complete", "annotations": .array([annotation])]]]
        var next: JSONObject = ["type": "message", "role": "assistant", "id": "next-message", "content": [["type": "output_text", "text": "after"]]]
        if strict {
            complete["status"] = "completed"
            complete["content"] = [["type": "output_text", "text": "complete", "annotations": .array([annotation]), "logprobs": []]]
            next["status"] = "completed"
            next["content"] = [["type": "output_text", "text": "after", "annotations": [], "logprobs": []]]
        }
        #expect(body["input"] == .array([easy, .object(complete), ["type": "function_call", "id": "function", "call_id": "call", "name": "tool", "arguments": #"{"arg":1}"#], .object(next)]))
    }

    @Test("summary-only encrypted reasoning stays summary-only while full content boundaries replay")
    func reasoningReplay() async throws {
        let endpoint = OpenResponsesTestEndpoint()
        let provider = try openResponsesProvider(endpoint)
        let summary: JSONValue = [["type": "summary_text", "text": "Summary"]]
        _ = try await provider("model").doGenerate(options: .init(prompt: [.assistant(content: [.reasoning(.init(text: "Summary", providerOptions: ["acme": ["itemId": "summary", "reasoningSummary": summary, "reasoningContent": .null, "reasoningEncryptedContent": "cipher"]]))], providerOptions: nil)]))
        let summaryBody = try await endpoint.lastBody()
        #expect(summaryBody["input"] == [["type": "reasoning", "id": "summary", "summary": summary, "encrypted_content": "cipher"]])
        let wire: JSONValue = ["type": "reasoning", "id": "reasoning", "summary": summary, "content": [["type": "reasoning_text", "text": "First"], ["type": "reasoning_text", "text": "Second"]], "encrypted_content": "cipher"]
        await endpoint.setResponse(openResponsesTestResponse(output: [wire]))
        let generated = try await provider("model").doGenerate(options: .init(prompt: openResponsesTestPrompt))
        let parts = generated.content.compactMap { part -> LanguageModelV4MessagePart? in
            if case .reasoning(let value) = part { return .reasoning(.init(text: value.text, providerOptions: value.providerMetadata)) }
            return nil
        }
        _ = try await provider("model").doGenerate(options: .init(prompt: [.assistant(content: parts, providerOptions: nil)]))
        let body = try await endpoint.lastBody()
        #expect(body["input"] == [wire])
    }

    @Test("user and tool files preserve image details, file URLs and inline media data")
    func mediaInput() async throws {
        let endpoint = OpenResponsesTestEndpoint()
        let provider = try openResponsesProvider(endpoint)
        let history: LanguageModelV4Prompt = [
            .user(content: [
                .file(.init(data: .base64("AAECAw=="), mediaType: "image/png", providerOptions: ["acme": ["imageDetail": "high"]])),
                .file(.init(data: .url(URL(string: "https://media.example/document.pdf")!), mediaType: "application/pdf", filename: "ignored.pdf")),
                .file(.init(data: .data(Data([0, 1, 2, 3])), mediaType: "application/pdf"))
            ], providerOptions: nil),
            .tool(content: [.toolResult(.init(toolCallId: "call", toolName: "tool", output: .content(value: [
                .text(text: "Result", providerOptions: nil),
                .file(data: .base64("AAECAw=="), mediaType: "image/png", filename: nil, providerOptions: ["acme": ["imageDetail": "low"]]),
                .file(data: .text("unsupported"), mediaType: "text/plain", filename: nil, providerOptions: nil),
                .custom(providerOptions: nil)
            ])))], providerOptions: nil)
        ]
        let result = try await provider("model").doGenerate(options: .init(prompt: history))
        let body = try await endpoint.lastBody()
        #expect(body["input"] == [
            ["type": "message", "role": "user", "content": [["type": "input_image", "image_url": "data:image/png;base64,AAECAw==", "detail": "high"], ["type": "input_file", "file_url": "https://media.example/document.pdf"], ["type": "input_file", "filename": "data", "file_data": "data:application/pdf;base64,AAECAw=="]]],
            ["type": "function_call_output", "call_id": "call", "output": [["type": "input_text", "text": "Result"], ["type": "input_image", "image_url": "data:image/png;base64,AAECAw==", "detail": "low"]]]
        ])
        #expect(result.warnings == [.other(message: "unsupported tool content part type: file with data type: text"), .other(message: "unsupported tool content part type: custom")])
    }

    @Test("reference and text user files fail instead of being silently reinterpreted", arguments: [false, true])
    func unsupportedData(reference: Bool) async throws {
        let endpoint = OpenResponsesTestEndpoint()
        let provider = try openResponsesProvider(endpoint)
        let data: SharedV4FileData = reference ? .reference(["endpoint": "file"]) : .text("text")
        await #expect(throws: UnsupportedFunctionalityError.self) { _ = try await provider("model").doGenerate(options: .init(prompt: [.user(content: [.file(.init(data: data, mediaType: "application/pdf"))], providerOptions: nil)])) }
    }
}
