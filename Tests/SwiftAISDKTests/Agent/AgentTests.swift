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

    @Test("settings and call callbacks both receive the end event")
    func callbacksAreMerged() async throws {
        let model = MockLanguageModelV4(doStream: .singleValue(textStream("streamed")))
        let calls = CallRecorder()
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

private final class CallRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var values: [String] { lock.withLock { storage } }

    func record(_ value: String) {
        lock.withLock { storage.append(value) }
    }
}
