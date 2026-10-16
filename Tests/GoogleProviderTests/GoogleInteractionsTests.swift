import Foundation
import Testing
import AISDKProvider
import GoogleProvider

@Suite("Google interactions V4")
struct GoogleInteractionsTests {
    @Test("interactions compact linked assistant and tool turns and parse output metadata")
    func linkedInteraction() async throws {
        let transport = GoogleTransport([.init(try googleFixture("interaction.json"))])
        let model = await transport.provider().interactions(modelId: "gemini-3.8-flash")
        let linked: SharedV4ProviderOptions = ["google": ["interactionId": .string("previous")]]
        let prompt: LanguageModelV4Prompt = [
            .system(content: "system", providerOptions: nil),
            .user(content: [.text(.init(text: "one")), .text(.init(text: "two"))], providerOptions: nil),
            .assistant(content: [.toolCall(.init(toolCallId: "old-call", toolName: "lookup", input: .object([:]), providerOptions: linked))], providerOptions: nil),
            .tool(content: [.toolResult(.init(toolCallId: "old-call", toolName: "lookup", output: .text(value: "old")))], providerOptions: nil),
            .user(content: [.file(.init(data: .url(URL(string: "https://media.example/video.mp4")!), mediaType: "video/mp4", providerOptions: ["google": ["processing": .object(["type": .string("static"), "startOffset": .number(1), "fps": .number(2)])]]))], providerOptions: nil)
        ]
        let result = try await model.doGenerate(options: .init(prompt: prompt, providerOptions: ["google": ["previousInteractionId": .string("previous"), "serviceTier": .string("priority"), "responseFormat": .array([.object(["type": .string("video"), "duration": .string("8s"), "resolution": .string("720p")])])]]))
        #expect(result.finishReason.unified == .stop)
        #expect(result.usage.inputTokens.noCache == 8)
        #expect(result.usage.outputTokens.total == 8)
        #expect(result.providerMetadata?["google"]?["outputTokensByModality"] == .object(["video": .number(4), "text": .number(1)]))
        let reasoning = try #require(result.content.compactMap { if case .reasoning(let value) = $0 { return value }; return nil }.first)
        #expect(reasoning.providerMetadata?["google"]?["signature"] == .string("interaction-signature"))
        #expect(reasoning.providerMetadata?["google"]?["interactionId"] == .string("interaction-1"))
        let request = try #require(await transport.captured().first)
        let body = try googleBody(request)
        let steps = array(body["input"])
        #expect(steps.count == 2)
        #expect(object(array(object(steps[0])["content"]).first)["text"] == .string("one\n\ntwo"))
        #expect(object(array(object(steps[1])["content"]).first)["processing"] == .object(["type": .string("static"), "start_offset": .string("1s"), "fps": .number(2)]))
        #expect(body["response_format"] == .array([.object(["type": .string("video"), "duration": .string("8s"), "resolution": .string("720p")])]))
        #expect(body["previous_interaction_id"] == .string("previous"))
    }

    @Test("interaction streams isolate concurrent text and thought steps and preserve call signatures")
    func streamInteractions() async throws {
        let transport = GoogleTransport([.init(try googleFixture("interaction.sse"), headers: ["Content-Type": "text/event-stream"])])
        let model = await transport.provider().interactions(modelId: "gemini-3.8-flash")
        let result = try await model.doStream(options: .init(prompt: googlePrompt))
        let parts = try await googleCollect(result.stream)
        #expect(parts.compactMap { if case .textDelta(let id, let delta, _) = $0 { return "\(id):\(delta)" }; return nil } == ["interaction-1:0:Answer"])
        #expect(parts.compactMap { if case .reasoningDelta(let id, let delta, _) = $0 { return "\(id):\(delta)" }; return nil } == ["interaction-1:1:Think"])
        let call = try #require(parts.compactMap { if case .toolCall(let call) = $0 { return call }; return nil }.first)
        #expect(call.toolCallId == "call-id")
        #expect(call.providerMetadata?["google"]?["signature"] == .string("call-signature"))
        #expect(parts.contains(.reasoningEnd(id: "interaction-1:1", providerMetadata: ["google": ["signature": .string("final-signature"), "interactionId": .string("interaction-1")]])))
        guard case .finish(let reason, _, let metadata) = parts.last else { Issue.record("missing finish"); return }
        #expect(reason.unified == .toolCalls)
        #expect(metadata?["google"]?["serviceTier"] == .string("flex"))
    }

    @Test("background streams resume from the last event after an interrupted connection")
    func resumeBackgroundStream() async throws {
        let transport = GoogleTransport([.init(try googleFixture("interaction-background.json")), .init(try googleFixture("interaction-reconnect-first.sse"), headers: ["Content-Type": "text/event-stream"]), .init(try googleFixture("interaction-reconnect-last.sse"), headers: ["Content-Type": "text/event-stream"])])
        let model = await transport.provider().interactions(.managedAgent("agents/custom"))
        let result = try await model.doStream(options: .init(prompt: googlePrompt, providerOptions: ["google": ["background": .bool(true)]]))
        let parts = try await googleCollect(result.stream)
        #expect(parts.compactMap { if case .textDelta(_, let delta, _) = $0 { return delta }; return nil }.joined() == "Answer")
        guard case .finish(let reason, _, _) = parts.last else { Issue.record("missing finish"); return }
        #expect(reason.unified == .stop)
        let requests = await transport.captured()
        #expect((try googleBody(requests[0]))["agent"] == .string("agents/custom"))
        #expect((try googleBody(requests[0]))["stream"] == nil)
        #expect(requests.last?.url?.query?.contains("last_event_id=event-3") == true)
    }
}
