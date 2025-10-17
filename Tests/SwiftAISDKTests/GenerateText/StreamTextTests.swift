// import AISDKProvider
// import AISDKProviderUtils
// import Foundation
// import Testing

// @testable import SwiftAISDK

// @Suite("StreamText – textStream basic")
// struct StreamTextBasicTests {
//     private let defaultUsage = LanguageModelV3Usage(
//         inputTokens: 1,
//         outputTokens: 4,
//         totalTokens: 5,
//         reasoningTokens: nil,
//         cachedInputTokens: nil
//     )

//     @Test("textStream yields raw deltas in order")
//     func textStreamYieldsRawDeltas() async throws {
//         // Arrange: mock streaming model that emits a single text block
//         let parts: [LanguageModelV3StreamPart] = [
//             .streamStart(warnings: []),
//             .responseMetadata(
//                 id: "id-0", modelId: "mock-model-id", timestamp: Date(timeIntervalSince1970: 0)),
//             .textStart(id: "1", providerMetadata: nil),
//             .textDelta(id: "1", delta: "Hello", providerMetadata: nil),
//             .textDelta(id: "1", delta: " ", providerMetadata: nil),
//             .textDelta(id: "1", delta: "World", providerMetadata: nil),
//             .textDelta(id: "1", delta: "!", providerMetadata: nil),
//             .textEnd(id: "1", providerMetadata: nil),
//             .finish(
//                 finishReason: .stop,
//                 usage: defaultUsage,
//                 providerMetadata: ["provider": ["key": .string("value")]]
//             ),
//         ]

//         let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { continuation in
//             for part in parts { continuation.yield(part) }
//             continuation.finish()
//         }

//         let model = MockLanguageModelV3(
//             doStream: .singleValue(
//                 LanguageModelV3StreamResult(stream: stream)
//             )
//         )

//         // Act
//         let result: DefaultStreamTextResult<JSONValue, JSONValue> = try streamText(
//             model: .v3(model),
//             prompt: "hello"
//         )

//         let chunks = try await convertReadableStreamToArray(result.textStream)

//         // Assert
//         #expect(chunks == ["Hello", " ", "World", "!"])
//     }
// }
