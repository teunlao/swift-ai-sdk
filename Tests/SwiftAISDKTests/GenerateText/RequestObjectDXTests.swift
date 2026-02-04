import Foundation
import Testing
@testable import SwiftAISDK
import AISDKProvider
import AISDKProviderUtils

@Suite("GenerateText/StreamText – request object DX")
struct RequestObjectDXTests {
    private let usage = LanguageModelV3Usage(inputTokens: .init(total: 1), outputTokens: .init(total: 1))

    private func makeEchoModel() -> MockLanguageModelV3 {
        MockLanguageModelV3(
            doGenerate: .function { options in
                let userText = options.prompt.compactMap { message -> String? in
                    guard case let .user(content, _) = message else { return nil }
                    for part in content {
                        if case let .text(textPart) = part {
                            return textPart.text
                        }
                    }
                    return nil
                }.first ?? ""

                return LanguageModelV3GenerateResult(
                    content: [.text(LanguageModelV3Text(text: userText))],
                    finishReason: .stop,
                    usage: self.usage,
                    providerMetadata: nil,
                    request: nil,
                    response: nil,
                    warnings: []
                )
            }
        )
    }

    @Test("generateText(request) supports base + override pattern")
    func generateTextRequestBaseOverride() async throws {
        let model = makeEchoModel()

        var base = GenerateTextRequest(model: .v3(model))
        base.providerOptions = ["mock": ["flag": .bool(true)]]
        base.toolChoice = .auto

        var a = base
        a.prompt = "A"
        let r1 = try await generateText(a)

        var b = base
        b.prompt = "B"
        let r2 = try await generateText(b)

        #expect(r1.text == "A")
        #expect(r2.text == "B")
        #expect(model.doGenerateCalls.count == 2)
        #expect(model.doGenerateCalls[0].providerOptions?["mock"]?["flag"] == .bool(true))
        #expect(model.doGenerateCalls[1].providerOptions?["mock"]?["flag"] == .bool(true))
    }

    @Test("generateText(request) supports typed experimentalOutput")
    func generateTextRequestTypedOutput() async throws {
        struct Summary: Codable, Sendable, Equatable { let value: String }

        let model = MockLanguageModelV3(
            doGenerate: .singleValue(
                LanguageModelV3GenerateResult(
                    content: [.text(LanguageModelV3Text(text: "{\"value\":\"ok\"}"))],
                    finishReason: .stop,
                    usage: usage,
                    providerMetadata: nil,
                    request: nil,
                    response: nil,
                    warnings: []
                )
            )
        )

        var req: GenerateTextRequest<Summary> = GenerateTextRequest(
            model: .v3(model),
            experimentalOutput: Output.object(Summary.self)
        )
        req.prompt = "give json"

        let result = try await generateText(req)
        #expect(try result.experimentalOutput == Summary(value: "ok"))
    }

    @Test("streamText(request) streams text deltas")
    func streamTextRequestStreamsText() async throws {
        let parts: [LanguageModelV3StreamPart] = [
            .streamStart(warnings: []),
            .responseMetadata(id: "id-0", modelId: "mock-model-id", timestamp: Date(timeIntervalSince1970: 0)),
            .textStart(id: "1", providerMetadata: nil),
            .textDelta(id: "1", delta: "Hello", providerMetadata: nil),
            .textDelta(id: "1", delta: " ", providerMetadata: nil),
            .textDelta(id: "1", delta: "World", providerMetadata: nil),
            .textEnd(id: "1", providerMetadata: nil),
            .finish(finishReason: .stop, usage: usage, providerMetadata: nil)
        ]

        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { continuation in
            for part in parts { continuation.yield(part) }
            continuation.finish()
        }

        let model = MockLanguageModelV3(
            doStream: .singleValue(LanguageModelV3StreamResult(stream: stream))
        )

        let stopCondition: SwiftAISDK.StopCondition = { steps in
            steps.count == 3
        }

        let request = StreamTextRequest(
            model: .v3(model),
            prompt: "hello",
            stopWhen: [stopCondition]
        )

        let result: DefaultStreamTextResult<JSONValue, JSONValue> = try streamText(request)
        let chunks = try await convertReadableStreamToArray(result.textStream)
        #expect(chunks == ["Hello", " ", "World"])
    }

    @Test("streamText(request) throws when neither prompt nor messages are provided")
    func streamTextRequestRequiresPromptOrMessages() async {
        let model = MockLanguageModelV3()
        let request = StreamTextRequest(model: .v3(model))

        #expect(throws: InvalidPromptError.self) {
            _ = try streamText(request)
        }
    }
}
