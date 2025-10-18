import Foundation
import Testing
@testable import SwiftAISDK
import AISDKProvider
import AISDKProviderUtils

@Suite("StreamText – SSE stream", .serialized)
struct StreamTextSSEIntegrationTests {
    @Test("toSSEStream mirrors encoder output")
    func toSSEStreamMatchesEncoder() async throws {
        let parts: [LanguageModelV3StreamPart] = [
            .streamStart(warnings: []),
            .responseMetadata(id: "id", modelId: "mock", timestamp: Date(timeIntervalSince1970: 0)),
            .textDelta(id: "a", delta: "Hi", providerMetadata: nil),
            .finish(
                finishReason: .stop,
                usage: LanguageModelV3Usage(inputTokens: 1, outputTokens: 1, totalTokens: 2),
                providerMetadata: nil
            )
        ]
        let providerStream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { continuation in
            parts.forEach { continuation.yield($0) }
            continuation.finish()
        }
        let model = MockLanguageModelV3(doStream: .singleValue(LanguageModelV3StreamResult(stream: providerStream)))
        let result: DefaultStreamTextResult<JSONValue, JSONValue> = try streamText(
            model: .v3(model),
            prompt: "hi"
        )

        let encoder = makeStreamTextSSEStream(from: result.fullStream, includeUsage: true)
        let direct = result.toSSEStream(includeUsage: true)

        let encoderEvents = try await convertReadableStreamToArray(encoder)
        let directEvents = try await convertReadableStreamToArray(direct)

        func canonical(_ events: [String]) throws -> [NSDictionary] {
            try events.map { line in
                guard line.hasPrefix("data: ") else { return NSDictionary() }
                let jsonPart = String(line.dropFirst(6))
                let data = Data(jsonPart.utf8)
                let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
                return object as? NSDictionary ?? NSDictionary()
            }
        }

        let lhs = try canonical(encoderEvents)
        let rhs = try canonical(directEvents)
        #expect(lhs == rhs)
    }
}
