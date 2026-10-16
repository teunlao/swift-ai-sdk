import Foundation
import AISDKProvider
import AISDKProviderUtils
import OpenAIProvider
import SwiftAISDK
import Testing

@Suite("OpenAI chat tool-result crash regression")
struct OpenAIChatToolResultCrashRegressionTests {
    @Test("UI tool result string survives OpenAI chat conversion without crashing")
    func uiToolResultStringSurvivesOpenAIChatConversion() async throws {
        let toolPart = UIToolUIPart(
            toolName: "calculator",
            toolCallId: "call-1",
            state: .outputAvailable,
            input: .object(["expression": .string("2+2")]),
            output: .string("4"),
            rawInput: nil,
            errorText: nil,
            providerExecuted: false,
            callProviderMetadata: ["openai": ["mode": .string("strict")]],
            preliminary: nil,
            approval: nil
        )

        let message = UIMessage(
            id: "assistant-1",
            role: .assistant,
            parts: [
                .text(TextUIPart(text: "Let me calculate that.")),
                .tool(toolPart)
            ]
        )

        let toolSchema = FlexibleSchema(jsonSchema(.object([
            "type": .string("object"),
            "properties": .object(["expression": .object(["type": .string("string")])]),
            "required": .array([.string("expression")]),
            "additionalProperties": .bool(false),
        ])))
        let tool = Tool(description: "Calculator", inputSchema: toolSchema)
        let modelMessages = try await convertToModelMessages(
            messages: [message],
            options: ConvertToModelMessagesOptions(tools: ["calculator": tool])
        )
        actor Capture {
            var body: Data?
            func store(_ body: Data?) { self.body = body }
        }
        let capture = Capture()
        let responseData = Data(#"{"id":"chatcmpl-ui-tool","object":"chat.completion","created":1700000000,"model":"gpt-4o-mini","choices":[{"index":0,"message":{"role":"assistant","content":"4"},"finish_reason":"stop"}],"usage":{"prompt_tokens":1,"completion_tokens":1,"total_tokens":2}}"#.utf8)
        let provider = try createOpenAI(settings: .init(apiKey: "test-key", fetch: { request in
            await capture.store(request.httpBody)
            return FetchResponse(
                body: .data(responseData),
                urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["content-type": "application/json"])!
            )
        }))
        let result = try await generateText(
            model: .v4(provider.chat("gpt-4o-mini")),
            tools: ["calculator": tool],
            messages: modelMessages
        )
        #expect(result.text == "4")

        let data = try #require(await capture.body)
        let json = try JSONSerialization.jsonObject(with: data)
        let body = try #require(json as? [String: Any])
        let messages = try #require(body["messages"] as? [[String: Any]])
        let toolMessage = try #require(messages.first { $0["role"] as? String == "tool" })
        #expect(toolMessage["tool_call_id"] as? String == "call-1")
        // A string tool output is sent as text output.
        #expect(toolMessage["content"] as? String == "4")
    }
}
