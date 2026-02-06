import Foundation
import Testing
@testable import SwiftAISDK
import AISDKProvider

@Suite("StreamText – retention")
struct StreamTextRetentionTests {
    private let defaultUsage = LanguageModelV3Usage(
        inputTokens: .init(total: 1),
        outputTokens: .init(total: 4)
    )

    private func makeStreamParts() -> AsyncThrowingStream<LanguageModelV3StreamPart, Error> {
        let parts: [LanguageModelV3StreamPart] = [
            .streamStart(warnings: []),
            .responseMetadata(id: "id-0", modelId: "mock-model-id", timestamp: Date(timeIntervalSince1970: 0)),
            .textStart(id: "1", providerMetadata: nil),
            .textDelta(id: "1", delta: "Hello", providerMetadata: nil),
            .textEnd(id: "1", providerMetadata: nil),
            .finish(finishReason: .stop, usage: defaultUsage, providerMetadata: nil)
        ]

        return AsyncThrowingStream { continuation in
            for part in parts { continuation.yield(part) }
            continuation.finish()
        }
    }

    @Test("request contains body by default")
    func requestContainsBodyByDefault() async throws {
        let model = MockLanguageModelV3(
            doStream: .singleValue(
                LanguageModelV3StreamResult(
                    stream: makeStreamParts(),
                    request: LanguageModelV3RequestInfo(body: "test body")
                )
            )
        )

        let result: DefaultStreamTextResult<JSONValue, JSONValue> = try streamText(
            model: .v3(model),
            prompt: "test-input"
        )

        let request = try await result.request
        #expect(request.body == JSONValue.string("test body"))
    }

    @Test("request excludes body when experimentalInclude.requestBody is false")
    func requestExcludesBodyWhenIncludeRequestBodyFalse() async throws {
        let model = MockLanguageModelV3(
            doStream: .singleValue(
                LanguageModelV3StreamResult(
                    stream: makeStreamParts(),
                    request: LanguageModelV3RequestInfo(body: "test body")
                )
            )
        )

        let result: DefaultStreamTextResult<JSONValue, JSONValue> = try streamText(
            model: .v3(model),
            prompt: "test-input",
            experimentalInclude: StreamTextInclude(requestBody: false)
        )

        let request = try await result.request
        #expect(request.body == nil)
    }
}

