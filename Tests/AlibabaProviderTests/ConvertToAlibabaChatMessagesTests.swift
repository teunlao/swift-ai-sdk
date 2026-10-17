import Foundation
import Testing
import AISDKProvider
import AlibabaProvider

@Suite("Alibaba history HTTP boundary")
struct ConvertToAlibabaChatMessagesTests {
    @Test("preserved thinking replays earlier rounds while current tool reasoning always survives", arguments: [false, true])
    func preservedThinking(enabled: Bool) async throws {
        let endpoint = AlibabaTestEndpoint()
        let history: LanguageModelV4Prompt = [
            .assistant(content: [.reasoning(.init(text: "Earlier")), .text(.init(text: "Old"))], providerOptions: nil),
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil),
            .assistant(content: [.reasoning(.init(text: "Current")), .toolCall(.init(toolCallId: "call", toolName: "lookup", input: [:]))], providerOptions: nil),
            .tool(content: [.toolResult(.init(toolCallId: "call", toolName: "lookup", output: .json(value: ["found": true])))], providerOptions: nil)
        ]
        let result = try await alibabaTestModel(endpoint).doGenerate(options: .init(prompt: history, providerOptions: ["alibaba": ["preserveThinking": .bool(enabled)]]))
        let body = try await endpoint.body()
        var previous: JSONObject = ["role": "assistant", "content": "Old"]
        if enabled { previous["reasoning_content"] = "Earlier" }
        #expect(body["preserve_thinking"] == .bool(enabled))
        #expect(body["messages"] == .array([
            .object(previous), ["role": "user", "content": [["type": "text", "text": "Hello"]]],
            ["role": "assistant", "content": .null, "reasoning_content": "Current", "tool_calls": [["id": "call", "type": "function", "function": ["name": "lookup", "arguments": "{}"]]]],
            ["role": "tool", "tool_call_id": "call", "content": #"{"found":true}"#]
        ]))
        #expect(result.content == [.text(.init(text: "Answer"))])
    }

    @Test("part cache wins and message cache applies to the last user and tool part")
    func cachePlacement() async throws {
        let endpoint = AlibabaTestEndpoint()
        let message: SharedV4ProviderOptions = ["alibaba": ["cacheControl": ["type": "message"]]]
        let part: SharedV4ProviderOptions = ["alibaba": ["cacheControl": ["type": "part"]]]
        let history: LanguageModelV4Prompt = [
            .user(content: [.text(.init(text: "A", providerOptions: part)), .text(.init(text: "B"))], providerOptions: message),
            .tool(content: [.toolResult(.init(toolCallId: "first", toolName: "tool", output: .text(value: "First"), providerOptions: part)), .toolResult(.init(toolCallId: "last", toolName: "tool", output: .executionDenied(reason: nil)))], providerOptions: message)
        ]
        _ = try await alibabaTestModel(endpoint).doGenerate(options: .init(prompt: history))
        #expect(try await endpoint.body()["messages"] == [
            ["role": "user", "content": [["type": "text", "text": "A", "cache_control": ["type": "part"]], ["type": "text", "text": "B", "cache_control": ["type": "message"]]]],
            ["role": "tool", "tool_call_id": "first", "content": [["type": "text", "text": "First", "cache_control": ["type": "part"]]]],
            ["role": "tool", "tool_call_id": "last", "content": [["type": "text", "text": "Tool call execution denied.", "cache_control": ["type": "message"]]]]
        ])
    }

    @Test("image data uses full MIME resolution and unsupported file data is refused")
    func imageParts() async throws {
        let endpoint = AlibabaTestEndpoint()
        let model = alibabaTestModel(endpoint)
        _ = try await model.doGenerate(options: .init(prompt: [.user(content: [.file(.init(data: .base64("iVBORw0KGgo="), mediaType: "image"))], providerOptions: nil)]))
        #expect(try await endpoint.body()["messages"] == [["role": "user", "content": [["type": "image_url", "image_url": ["url": "data:image/png;base64,iVBORw0KGgo="]]]]])
        await #expect(throws: UnsupportedFunctionalityError.self) { try await model.doGenerate(options: .init(prompt: [.user(content: [.file(.init(data: .reference(["alibaba": "file"]), mediaType: "image/png"))], providerOptions: nil)])) }
        await #expect(throws: UnsupportedFunctionalityError.self) { try await model.doGenerate(options: .init(prompt: [.user(content: [.file(.init(data: .base64("JVBERi0="), mediaType: "application/pdf"))], providerOptions: nil)])) }
    }
}
