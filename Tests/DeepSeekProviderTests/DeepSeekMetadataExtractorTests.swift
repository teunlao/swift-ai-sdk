import Foundation
import Testing
@testable import DeepSeekProvider
@testable import AISDKProvider
@testable import OpenAICompatibleProvider

/**
 DeepSeek Metadata Extractor tests.

 Port of `@ai-sdk/deepseek/src/deepseek-metadata-extractor.test.ts`.
 */

@Suite("DeepSeekMetadataExtractor")
struct DeepSeekMetadataExtractorTests {

    // MARK: - buildMetadataFromResponse Tests

    @Test("should extract metadata from complete response with usage data")
    func extractMetadataFromCompleteResponse() async throws {
        let response: JSONValue = .object([
            "usage": .object([
                "prompt_cache_hit_tokens": .number(100),
                "prompt_cache_miss_tokens": .number(50)
            ])
        ])

        let metadata = try await deepSeekMetadataExtractor.extractMetadata(parsedBody: response)

        guard let metadata,
              let deepseek = metadata["deepseek"],
              case .number(let hitTokens) = deepseek["promptCacheHitTokens"],
              case .number(let missTokens) = deepseek["promptCacheMissTokens"] else {
            Issue.record("Expected deepseek metadata")
            return
        }

        #expect(hitTokens == 100)
        #expect(missTokens == 50)
    }

    @Test("should handle missing usage data")
    func handleMissingUsageData() async throws {
        let response: JSONValue = .object([
            "id": .string("test-id"),
            "choices": .array([])
        ])

        let metadata = try await deepSeekMetadataExtractor.extractMetadata(parsedBody: response)

        #expect(metadata == nil)
    }

    @Test("should handle invalid response data")
    func handleInvalidResponseData() async throws {
        let response: JSONValue = .string("invalid data")

        let metadata = try await deepSeekMetadataExtractor.extractMetadata(parsedBody: response)

        #expect(metadata == nil)
    }

    // MARK: - streaming metadata extractor Tests

    @Test("should process streaming chunks and build final metadata")
    func processStreamingChunksAndBuildFinalMetadata() async throws {
        let extractor = await deepSeekMetadataExtractor.createStreamExtractor()

        // Process initial chunks without usage data
        await extractor.processChunk(.object([
            "choices": .array([
                .object(["finish_reason": .null])
            ])
        ]))

        // Process final chunk with usage data
        await extractor.processChunk(.object([
            "choices": .array([
                .object(["finish_reason": .string("stop")])
            ]),
            "usage": .object([
                "prompt_cache_hit_tokens": .number(100),
                "prompt_cache_miss_tokens": .number(50)
            ])
        ]))

        let finalMetadata = extractor.buildMetadata()

        guard let finalMetadata,
              let deepseek = finalMetadata["deepseek"],
              case .number(let hitTokens) = deepseek["promptCacheHitTokens"],
              case .number(let missTokens) = deepseek["promptCacheMissTokens"] else {
            Issue.record("Expected deepseek metadata")
            return
        }

        #expect(hitTokens == 100)
        #expect(missTokens == 50)
    }

    @Test("should handle streaming chunks without usage data")
    func handleStreamingChunksWithoutUsageData() async throws {
        let extractor = await deepSeekMetadataExtractor.createStreamExtractor()

        await extractor.processChunk(.object([
            "choices": .array([
                .object(["finish_reason": .string("stop")])
            ])
        ]))

        let finalMetadata = extractor.buildMetadata()

        #expect(finalMetadata == nil)
    }

    @Test("should handle invalid streaming chunks")
    func handleInvalidStreamingChunks() async throws {
        let extractor = await deepSeekMetadataExtractor.createStreamExtractor()

        await extractor.processChunk(.string("invalid chunk"))

        let finalMetadata = extractor.buildMetadata()

        #expect(finalMetadata == nil)
    }

    @Test("should only capture usage data from final chunk with stop reason")
    func onlyCaptureUsageDataFromFinalChunkWithStopReason() async throws {
        let extractor = await deepSeekMetadataExtractor.createStreamExtractor()

        // Process chunk with usage but no stop reason
        await extractor.processChunk(.object([
            "choices": .array([
                .object(["finish_reason": .null])
            ]),
            "usage": .object([
                "prompt_cache_hit_tokens": .number(50),
                "prompt_cache_miss_tokens": .number(25)
            ])
        ]))

        // Process final chunk with different usage data
        await extractor.processChunk(.object([
            "choices": .array([
                .object(["finish_reason": .string("stop")])
            ]),
            "usage": .object([
                "prompt_cache_hit_tokens": .number(100),
                "prompt_cache_miss_tokens": .number(50)
            ])
        ]))

        let finalMetadata = extractor.buildMetadata()

        guard let finalMetadata,
              let deepseek = finalMetadata["deepseek"],
              case .number(let hitTokens) = deepseek["promptCacheHitTokens"],
              case .number(let missTokens) = deepseek["promptCacheMissTokens"] else {
            Issue.record("Expected deepseek metadata")
            return
        }

        #expect(hitTokens == 100)
        #expect(missTokens == 50)
    }

    @Test("should handle null values in usage data")
    func handleNullValuesInUsageData() async throws {
        let extractor = await deepSeekMetadataExtractor.createStreamExtractor()

        await extractor.processChunk(.object([
            "choices": .array([
                .object(["finish_reason": .string("stop")])
            ]),
            "usage": .object([
                "prompt_cache_hit_tokens": .null,
                "prompt_cache_miss_tokens": .number(50)
            ])
        ]))

        let finalMetadata = extractor.buildMetadata()

        guard let finalMetadata,
              let deepseek = finalMetadata["deepseek"],
              case .number(let hitTokens) = deepseek["promptCacheHitTokens"],
              case .number(let missTokens) = deepseek["promptCacheMissTokens"] else {
            Issue.record("Expected deepseek metadata")
            return
        }

        #expect(hitTokens.isNaN)
        #expect(missTokens == 50)
    }
}
