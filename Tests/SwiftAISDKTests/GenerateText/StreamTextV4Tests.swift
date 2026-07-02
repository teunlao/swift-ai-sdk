import Foundation
import Testing
@testable import SwiftAISDK
import AISDKProvider
import AISDKProviderUtils

@Suite("StreamText V4 Tests")
struct StreamTextV4Tests {
    private actor CapturedV4StreamOptions {
        private var value: LanguageModelV4CallOptions?

        func record(_ options: LanguageModelV4CallOptions) {
            value = options
        }

        func recorded() -> LanguageModelV4CallOptions? {
            value
        }
    }

    @Test("streamText calls V4 model and preserves V4 stream content")
    func streamTextUsesLanguageModelV4Contract() async throws {
        let captured = CapturedV4StreamOptions()
        let responseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let model = MockLanguageModelV4(
            provider: "mock-v4-provider",
            modelId: "mock-v4-stream-model",
            doStream: .function { options in
                await captured.record(options)

                let stream = AsyncThrowingStream<LanguageModelV4StreamPart, Error> { continuation in
                    continuation.yield(.streamStart(warnings: [
                        .deprecated(setting: "topK", message: "Use provider defaults.")
                    ]))
                    continuation.yield(.responseMetadata(
                        id: "response-v4",
                        modelId: "mock-v4-stream-model",
                        timestamp: responseDate
                    ))
                    continuation.yield(.textStart(id: "text-1", providerMetadata: nil))
                    continuation.yield(.textDelta(id: "text-1", delta: "Hello", providerMetadata: nil))
                    continuation.yield(.textEnd(id: "text-1", providerMetadata: nil))
                    continuation.yield(.custom(LanguageModelV4CustomContent(kind: "stream-custom")))
                    continuation.yield(.reasoningFile(LanguageModelV4ReasoningFile(
                        mediaType: "text/plain",
                        data: .base64("cmVhc29uaW5n")
                    )))
                    continuation.yield(.finish(
                        finishReason: LanguageModelV4FinishReason(unified: .stop, raw: "stop"),
                        usage: LanguageModelV4Usage(
                            inputTokens: .init(total: 3),
                            outputTokens: .init(total: 5)
                        ),
                        providerMetadata: ["mock": ["finish": .string("v4")]]
                    ))
                    continuation.finish()
                }

                return LanguageModelV4StreamResult(
                    stream: stream,
                    request: LanguageModelV4RequestInfo(body: ["mode": "v4-stream"]),
                    response: LanguageModelV4StreamResponseInfo(headers: ["x-response": "v4"])
                )
            }
        )

        let result: DefaultStreamTextResult<JSONValue, JSONValue> = try streamText(
            model: .v4(model),
            system: "You are a V4 stream test.",
            prompt: "Stream hello.",
            providerOptions: ["mock": ["mode": .string("stream")]],
            settings: CallSettings(
                temperature: 0.1,
                reasoning: .medium,
                headers: ["x-test": "stream-v4"]
            )
        )

        let parts = try await result.collectFullStream()
        let finish = try await result.waitForFinish()
        let options = try #require(await captured.recorded())

        #expect(options.reasoning == .medium)
        #expect(options.temperature == 0.1)
        #expect(options.headers?["x-test"] == "stream-v4")
        #expect(options.providerOptions?["mock"]?["mode"] == .string("stream"))
        #expect(options.prompt.count == 2)

        #expect(finish.finalStep.text == "Hello")
        #expect(finish.finishReason == .stop)
        #expect(finish.finalStep.rawFinishReason == "stop")
        #expect(finish.totalUsage.inputTokens == 3)
        #expect(finish.totalUsage.outputTokens == 5)

        #expect(parts.contains { part in
            if case .custom(let kind, _) = part {
                return kind == "stream-custom"
            }
            return false
        })
        #expect(parts.contains { part in
            if case .reasoningFile(let file, _) = part {
                return file.mediaType == "text/plain" && file.base64 == "cmVhc29uaW5n"
            }
            return false
        })
        #expect(finish.finalStep.content.contains { part in
            if case .custom(let kind, _) = part {
                return kind == "stream-custom"
            }
            return false
        })
        #expect(finish.finalStep.content.contains { part in
            if case .reasoningFile(let file, _) = part {
                return file.mediaType == "text/plain" && file.base64 == "cmVhc29uaW5n"
            }
            return false
        })

        let warning = try #require(finish.finalStep.warnings?.first)
        if case .deprecated(let setting, let message) = warning {
            #expect(setting == "topK")
            #expect(message == "Use provider defaults.")
        } else {
            Issue.record("Expected V4 deprecated warning")
        }
    }
}
