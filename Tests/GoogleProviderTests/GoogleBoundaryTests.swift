import Foundation
import Testing
import AISDKProvider
import GoogleProvider

@Suite("Google response boundary validation")
struct GoogleBoundaryTests {
    @Test("explicit candidate completion takes precedence over prompt feedback")
    func candidatePrecedence() async throws {
        var response = try JSONDecoder().decode(JSONObject.self, from: googleFixture("text.json"))
        response["promptFeedback"] = .object(["blockReason": .string("SAFETY")])
        let transport = GoogleTransport([.init(try googleData(.object(response)))])
        let model = await transport.provider().chat(modelId: "gemini-3.8-flash")
        let result = try await model.doGenerate(options: .init(prompt: googlePrompt))
        #expect(result.finishReason == .init(unified: .stop, raw: "STOP"))
        #expect(result.content.compactMap { if case .text(let value) = $0 { return value.text }; return nil } == ["Hello"])
    }

    @Test("interaction usage rejects invalid or unrepresentable native counts", arguments: [JSONValue.string("bad"), .number(1e40)])
    func invalidUsage(_ count: JSONValue) async throws {
        let response: JSONValue = .object(["status": .string("completed"), "usage": .object(["total_input_tokens": count])])
        let transport = GoogleTransport([.init(try googleData(response))])
        let model = await transport.provider().interactions(modelId: "gemini-3.8-flash")
        do {
            _ = try await model.doGenerate(options: .init(prompt: googlePrompt))
            Issue.record("expected invalid response")
        } catch let error as APICallError {
            #expect(error.cause is TypeValidationError)
        }
    }

    @Test("stream step indexes preserve the upstream numeric range")
    func wideIndex() async throws {
        let transport = GoogleTransport([.init(try googleFixture("interaction-wide-index.sse"), headers: ["Content-Type": "text/event-stream"])])
        let model = await transport.provider().interactions(modelId: "gemini-3.8-flash")
        let parts = try await googleCollect(model.doStream(options: .init(prompt: googlePrompt)).stream)
        #expect(parts.compactMap { if case .textDelta(let id, let delta, _) = $0 { return "\(id):\(delta)" }; return nil } == ["interaction:1e+40:wide index"])
        guard case .finish(let reason, let usage, _) = parts.last else { Issue.record("missing finish"); return }
        #expect(reason.unified == .stop && usage.outputTokens.total == 1)
    }

    @Test("agent environment source target is validated before transport")
    func invalidEnvironmentTarget() async throws {
        let model = createGoogle(settings: .init(apiKey: "key")).interactions(.managedAgent("agents/custom"))
        await #expect(throws: InvalidArgumentError.self) {
            try await model.doGenerate(options: .init(prompt: googlePrompt, providerOptions: ["google": ["environment": .object(["type": .string("remote"), "sources": .array([.object(["type": .string("gcs"), "source": .string("gs://bucket/input"), "target": .number(123)])])])]]))
        }
    }
}
