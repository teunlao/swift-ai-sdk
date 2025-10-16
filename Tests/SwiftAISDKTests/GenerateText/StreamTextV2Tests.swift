/**
 StreamText V2 Tests

 Phase 1: Basic textStream functionality with race condition fixes.
 */

import Testing
import Foundation
@testable import SwiftAISDK
@testable import AISDKProvider

// MARK: - Test Helpers

private let testUsage = LanguageModelUsage(
    inputTokens: 3,
    outputTokens: 10,
    totalTokens: 13
)

private func createTestModelV2(
    stream: [LanguageModelV3StreamPart]? = nil
) -> MockLanguageModelV3 {
    let defaultStream: [LanguageModelV3StreamPart] = [
        .streamStart(warnings: []),
        .responseMetadata(id: "id-0", modelId: "mock-model-id", timestamp: Date(timeIntervalSince1970: 0)),
        .textStart(id: "1", providerMetadata: nil),
        .textDelta(id: "1", delta: "Hello", providerMetadata: nil),
        .textDelta(id: "1", delta: ", ", providerMetadata: nil),
        .textDelta(id: "1", delta: "world!", providerMetadata: nil),
        .textEnd(id: "1", providerMetadata: nil),
        .finish(
            finishReason: .stop,
            usage: testUsage,
            providerMetadata: ["testProvider": ["testKey": "testValue"]]
        )
    ]

    return MockLanguageModelV3(
        doStream: .function { _ in
            let parts = stream ?? defaultStream
            return LanguageModelV3StreamResult(
                stream: AsyncThrowingStream { continuation in
                    for part in parts {
                        continuation.yield(part)
                    }
                    continuation.finish()
                },
                request: nil,
                response: nil
            )
        }
    )
}

// MARK: - Basic textStream Tests

@Suite("StreamTextV2 - textStream basic")
struct StreamTextV2BasicTests {

    @Test("should send text deltas")
    func sendsTextDeltas() async throws {
        let model = MockLanguageModelV3(
            doStream: .function { options in
                // Verify prompt
                #expect(options.prompt.count == 1)
                if case .user(let content, _) = options.prompt[0] {
                    #expect(content.count == 1)
                    if case .text(let textPart) = content[0] {
                        #expect(textPart.text == "test-input")
                    } else {
                        Issue.record("Expected text content")
                    }
                } else {
                    Issue.record("Expected user message")
                }

                let parts: [LanguageModelV3StreamPart] = [
                    .textStart(id: "1", providerMetadata: nil),
                    .textDelta(id: "1", delta: "Hello", providerMetadata: nil),
                    .textDelta(id: "1", delta: ", ", providerMetadata: nil),
                    .textDelta(id: "1", delta: "world!", providerMetadata: nil),
                    .textEnd(id: "1", providerMetadata: nil),
                    .finish(finishReason: .stop, usage: testUsage, providerMetadata: nil)
                ]

                return LanguageModelV3StreamResult(
                    stream: AsyncThrowingStream { continuation in
                        for part in parts {
                            continuation.yield(part)
                        }
                        continuation.finish()
                    },
                    request: nil,
                    response: nil
                )
            }
        )

        let result = try streamTextV2(
            model: .v3(model),
            prompt: "test-input"
        )

        var collected: [String] = []
        for try await chunk in result.textStream {
            collected.append(chunk)
        }

        #expect(collected == ["Hello", ", ", "world!"])
    }

    @Test("should filter out empty text deltas")
    func filtersEmptyTextDeltas() async throws {
        let model = createTestModelV2(
            stream: [
                .textStart(id: "1", providerMetadata: nil),
                .textDelta(id: "1", delta: "", providerMetadata: nil),
                .textDelta(id: "1", delta: "Hello", providerMetadata: nil),
                .textDelta(id: "1", delta: "", providerMetadata: nil),
                .textDelta(id: "1", delta: ", ", providerMetadata: nil),
                .textDelta(id: "1", delta: "", providerMetadata: nil),
                .textDelta(id: "1", delta: "world!", providerMetadata: nil),
                .textDelta(id: "1", delta: "", providerMetadata: nil),
                .textEnd(id: "1", providerMetadata: nil),
                .finish(finishReason: .stop, usage: testUsage, providerMetadata: nil)
            ]
        )

        let result = try streamTextV2(
            model: .v3(model),
            prompt: "test-input"
        )

        var collected: [String] = []
        for try await chunk in result.textStream {
            collected.append(chunk)
        }

        #expect(collected == ["Hello", ", ", "world!"])
    }

    @Test("should accumulate full text")
    func accumulatesFullText() async throws {
        let model = createTestModelV2()

        let result = try streamTextV2(
            model: .v3(model),
            prompt: "test-input"
        )

        // Consume stream first
        for try await _ in result.textStream {}

        // Then check accumulated text
        let fullText = try await result.text
        #expect(fullText == "Hello, world!")
    }

    @Test("should capture finish reason")
    func capturesFinishReason() async throws {
        let model = createTestModelV2()

        let result = try streamTextV2(
            model: .v3(model),
            prompt: "test-input"
        )

        // Consume stream
        for try await _ in result.textStream {}

        let reason = try await result.finishReason
        #expect(reason == .stop)
    }

    @Test("should capture usage")
    func capturesUsage() async throws {
        let model = createTestModelV2()

        let result = try streamTextV2(
            model: .v3(model),
            prompt: "test-input"
        )

        // Consume stream
        for try await _ in result.textStream {}

        let usage = try await result.usage
        #expect(usage.inputTokens == 3)
        #expect(usage.outputTokens == 10)
        #expect(usage.totalTokens == 13)
    }
}

// MARK: - Phase 2: fullStream and content Tests

@Suite("StreamTextV2 - fullStream")
struct StreamTextV2FullStreamTests {

    @Test("should emit all stream parts")
    func emitsAllStreamParts() async throws {
        let model = createTestModelV2(
            stream: [
                .streamStart(warnings: []),
                .textStart(id: "1", providerMetadata: nil),
                .textDelta(id: "1", delta: "Hello", providerMetadata: nil),
                .textEnd(id: "1", providerMetadata: nil),
                .finish(finishReason: .stop, usage: testUsage, providerMetadata: nil)
            ]
        )

        let result = try streamTextV2(
            model: .v3(model),
            prompt: "test-input"
        )

        var parts: [TextStreamPart] = []
        for try await part in result.fullStream {
            parts.append(part)
        }

        // Should have: start, textStart, textDelta, textEnd, finish
        #expect(parts.count >= 4)
    }

    @Test("should capture content with text")
    func capturesContentWithText() async throws {
        let model = createTestModelV2()

        let result = try streamTextV2(
            model: .v3(model),
            prompt: "test-input"
        )

        // Consume stream
        for try await _ in result.textStream {}

        let content = try await result.content
        #expect(content.count > 0)

        // Should have text content
        let hasText = content.contains { part in
            if case .text = part { return true }
            return false
        }
        #expect(hasText)
    }
}

@Suite("StreamTextV2 - reasoning support")
struct StreamTextV2ReasoningTests {

    @Test("should capture reasoning content")
    func capturesReasoningContent() async throws {
        let model = createTestModelV2(
            stream: [
                .textStart(id: "1", providerMetadata: nil),
                .textDelta(id: "1", delta: "Answer", providerMetadata: nil),
                .textEnd(id: "1", providerMetadata: nil),
                .reasoningStart(id: "r1", providerMetadata: nil),
                .reasoningDelta(id: "r1", delta: "Let me think", providerMetadata: nil),
                .reasoningDelta(id: "r1", delta: "...", providerMetadata: nil),
                .reasoningEnd(id: "r1", providerMetadata: nil),
                .finish(finishReason: .stop, usage: testUsage, providerMetadata: nil)
            ]
        )

        let result = try streamTextV2(
            model: .v3(model),
            prompt: "test-input"
        )

        // Consume stream
        for try await _ in result.fullStream {}

        let reasoning = try await result.reasoning
        #expect(reasoning.count == 1)
        #expect(reasoning[0].text == "Let me think...")
    }

    @Test("should return reasoningText")
    func returnsReasoningText() async throws {
        let model = createTestModelV2(
            stream: [
                .reasoningStart(id: "r1", providerMetadata: nil),
                .reasoningDelta(id: "r1", delta: "Thinking", providerMetadata: nil),
                .reasoningEnd(id: "r1", providerMetadata: nil),
                .finish(finishReason: .stop, usage: testUsage, providerMetadata: nil)
            ]
        )

        let result = try streamTextV2(
            model: .v3(model),
            prompt: "test-input"
        )

        // Consume stream
        for try await _ in result.fullStream {}

        let reasoningText = try await result.reasoningText
        #expect(reasoningText == "Thinking")
    }

    @Test("should return nil reasoningText when no reasoning")
    func returnsNilWhenNoReasoning() async throws {
        let model = createTestModelV2()

        let result = try streamTextV2(
            model: .v3(model),
            prompt: "test-input"
        )

        // Consume stream
        for try await _ in result.textStream {}

        let reasoningText = try await result.reasoningText
        #expect(reasoningText == nil)
    }
}

@Suite("StreamTextV2 - files and sources")
struct StreamTextV2FilesSourcesTests {

    @Test("should capture files")
    func capturesFiles() async throws {
        let testFile = LanguageModelV3File(
            mediaType: "image/png",
            data: .base64("base64data")
        )

        let model = createTestModelV2(
            stream: [
                .file(testFile),
                .finish(finishReason: .stop, usage: testUsage, providerMetadata: nil)
            ]
        )

        let result = try streamTextV2(
            model: .v3(model),
            prompt: "test-input"
        )

        // Consume stream
        for try await _ in result.fullStream {}

        let files = try await result.files
        #expect(files.count == 1)
        #expect(files[0].mediaType == "image/png")
    }

    @Test("should capture sources")
    func capturesSources() async throws {
        let testSource = Source.url(
            id: "s1",
            url: "https://example.com",
            title: "Example",
            providerMetadata: nil
        )

        let model = createTestModelV2(
            stream: [
                .source(testSource),
                .finish(finishReason: .stop, usage: testUsage, providerMetadata: nil)
            ]
        )

        let result = try streamTextV2(
            model: .v3(model),
            prompt: "test-input"
        )

        // Consume stream
        for try await _ in result.fullStream {}

        let sources = try await result.sources
        #expect(sources.count == 1)
    }
}

// MARK: - Race Condition Tests

@Suite("StreamTextV2 - race condition safety")
struct StreamTextV2RaceConditionTests {

    @Test("should handle concurrent textStream reads")
    func handlesConcurrentReads() async throws {
        let model = createTestModelV2()

        let result = try streamTextV2(
            model: .v3(model),
            prompt: "test-input"
        )

        // Multiple concurrent consumers
        await withTaskGroup(of: [String].self) { group in
            for _ in 0..<5 {
                group.addTask {
                    var collected: [String] = []
                    do {
                        for try await chunk in result.textStream {
                            collected.append(chunk)
                        }
                    } catch {
                        // Expected - only one consumer can read the stream
                    }
                    return collected
                }
            }

            var results: [[String]] = []
            for await chunks in group {
                if !chunks.isEmpty {
                    results.append(chunks)
                }
            }

            // At least one should succeed
            #expect(results.count >= 1)
        }
    }

    @Test("should handle concurrent property access")
    func handlesConcurrentPropertyAccess() async throws {
        let model = createTestModelV2()

        let result = try streamTextV2(
            model: .v3(model),
            prompt: "test-input"
        )

        // Consume stream in background
        Task {
            for try await _ in result.textStream {}
        }

        // Try to access properties concurrently while stream is running
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    do {
                        _ = try await result.text
                        _ = try await result.finishReason
                        _ = try await result.usage
                    } catch {
                        // Expected - properties resolve after stream completes
                    }
                }
            }

            await group.waitForAll()
        }

        // All should eventually succeed
        let text = try await result.text
        let reason = try await result.finishReason
        let usage = try await result.usage

        #expect(!text.isEmpty)
        #expect(reason == .stop)
        #expect(usage.totalTokens == 13)
    }
}
