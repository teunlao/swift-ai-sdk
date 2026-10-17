import Foundation
import AISDKProvider
import AISDKProviderUtils
@testable import SwiftAISDK
import Testing

@Suite("ToolLoopAgent")
struct AgentTests {
    private func textStream(_ text: String) -> LanguageModelV4StreamResult {
        let parts: [LanguageModelV4StreamPart] = [
            .streamStart(warnings: []),
            .textStart(id: "1", providerMetadata: nil),
            .textDelta(id: "1", delta: text, providerMetadata: nil),
            .textEnd(id: "1", providerMetadata: nil),
            .finish(
                finishReason: LanguageModelV4FinishReason(unified: .stop),
                usage: LanguageModelV4Usage(),
                providerMetadata: nil
            ),
        ]
        return LanguageModelV4StreamResult(stream: AsyncThrowingStream { continuation in
            parts.forEach { continuation.yield($0) }
            continuation.finish()
        })
    }

    private func textResult(_ text: String) -> LanguageModelV4GenerateResult {
        LanguageModelV4GenerateResult(
            content: [.text(LanguageModelV4Text(text: text))],
            finishReason: LanguageModelV4FinishReason(unified: .stop),
            usage: LanguageModelV4Usage()
        )
    }

    @Test("generate forwards the agent settings and tags the user agent")
    func generateForwardsSettings() async throws {
        let model = MockLanguageModelV4(doGenerate: .singleValue(textResult("ok")))
        let agent = ToolLoopAgent<Never, String, String>(ToolLoopAgentSettings(
            instructions: "You are helpful",
            model: model,
            tools: ["echo": Tool(description: "Echo", inputSchema: FlexibleSchema(jsonSchema(.object(["type": .string("object")]))))],
            // A forced choice would reject the text-only response; `.none` still proves forwarding.
            toolChoice: ToolChoice.none,
            providerOptions: ["openai": ["mode": .string("fast")]],
            callSettings: CallSettings(maxOutputTokens: 42, temperature: 0.1)
        ))

        let result = try await agent.generate(prompt: "Hello")

        #expect(result.text == "ok")
        let options = try #require(model.doGenerateCalls.first)
        guard case .system(let system, _) = options.prompt.first else {
            Issue.record("Expected the instructions as the first message")
            return
        }
        #expect(system == "You are helpful")
        #expect(options.maxOutputTokens == 42)
        #expect(options.temperature == 0.1)
        #expect(options.tools?.count == 1)
        #expect(options.toolChoice == LanguageModelV4ToolChoice.none)
        #expect(options.providerOptions?["openai"]?["mode"] == .string("fast"))
        #expect(options.headers?["user-agent"]?.contains("ai-sdk-agent/tool-loop") == true)
    }

    @Test("call options are validated and shape the call through prepareCall")
    func prepareCallUsesValidatedOptions() async throws {
        struct CallOptions: Codable, Sendable { let userName: String }

        let model = MockLanguageModelV4(doGenerate: .singleValue(textResult("ok")))
        let agent = ToolLoopAgent<CallOptions, String, String>(ToolLoopAgentSettings(
            model: model,
            callOptionsSchema: FlexibleSchema(Schema.codable(
                CallOptions.self,
                jsonSchema: .object([
                    "type": .string("object"),
                    "properties": .object(["userName": .object(["type": .string("string")])]),
                    "required": .array([.string("userName")]),
                ])
            )),
            prepareCall: { call in
                var call = call
                call.instructions = .text("Address the user as \(call.options?.userName ?? "?")")
                return call
            }
        ))

        _ = try await agent.generate(prompt: "Hello", options: CallOptions(userName: "Ada"))

        let options = try #require(model.doGenerateCalls.first)
        guard case .system(let system, _) = options.prompt.first else {
            Issue.record("Expected prepared instructions as the first message")
            return
        }
        #expect(system == "Address the user as Ada")
    }

    @Test("respond passes call options to prepareCall and ends with the continued conversation")
    @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
    func respondUsesCallOptionsAndHistory() async throws {
        struct CallOptions: Codable, Sendable { let userName: String }

        let model = MockLanguageModelV4(doStream: .singleValue(textStream(" again")))
        let agent = ToolLoopAgent<CallOptions, String, String>(ToolLoopAgentSettings(
            model: model,
            prepareCall: { call in
                var call = call
                call.instructions = .text("Address the user as \(call.options?.userName ?? "?")")
                return call
            }
        ))
        let history = [
            UIMessage(id: "u1", role: .user, parts: [.text(TextUIPart(text: "Hi", state: .done))]),
            UIMessage(id: "a1", role: .assistant, parts: [.text(TextUIPart(text: "Hello", state: .done))]),
        ]
        let ends = EventRecorder<UIMessageStreamEndEvent<UIMessage>>()

        let response = try await agent.respond(
            messages: history,
            options: CallOptions(userName: "Ada"),
            responseOptions: StreamTextUIResponseOptions(streamOptions: UIMessageStreamOptions(
                onEnd: { event in ends.record(event) }
            ))
        )
        for try await _ in response.stream {}

        let call = try #require(model.doStreamCalls.first)
        guard case .system(let system, _) = call.prompt.first else {
            Issue.record("Expected prepared instructions as the first message")
            return
        }
        #expect(system == "Address the user as Ada")
        let end = try #require(ends.values.first)
        #expect(end.isContinuation)
        #expect(end.messages.map(\.id) == ["u1", "a1"])
        #expect(end.responseMessage.parts.first == .text(TextUIPart(text: "Hello", state: .done)))
    }

    @Test("settings and call callbacks both receive the end event")
    func callbacksAreMerged() async throws {
        let model = MockLanguageModelV4(doStream: .singleValue(textStream("streamed")))
        let calls = EventRecorder<String>()
        let agent = ToolLoopAgent<Never, String, String>(ToolLoopAgentSettings(
            model: model,
            onEnd: { _ in calls.record("settings") }
        ))

        let result = try await agent.stream(AgentStreamParameters(AgentCallParameters(
            prompt: .text("Ping"),
            onEnd: { event in calls.record("call:\(event.text)") }
        )))
        #expect(try await result.collectText() == "streamed")
        _ = try await result.steps

        #expect(Set(calls.values) == ["settings", "call:streamed"])
    }

    @Test("a prompt given as both prompt and messages is rejected")
    func promptAndMessagesAreRejected() async throws {
        let model = MockLanguageModelV4(doGenerate: .singleValue(textResult("ok")))
        let agent = ToolLoopAgent<Never, String, String>(ToolLoopAgentSettings(model: model))

        await #expect(throws: InvalidPromptError.self) {
            _ = try await agent.generate(AgentCallParameters(
                prompt: .text("Hello"),
                messages: [.user(UserModelMessage(content: .text("Hi")))]
            ))
        }
        #expect(model.doGenerateCalls.isEmpty)
    }
}

private final class EventRecorder<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Value] = []

    var values: [Value] { lock.withLock { storage } }

    func record(_ value: Value) {
        lock.withLock { storage.append(value) }
    }
}
