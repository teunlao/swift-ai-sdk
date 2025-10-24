/**
 Tests for mock language model implementations.

 These tests verify the mock utilities work correctly for testing purposes.
 No upstream tests exist (mock utilities are testing infrastructure).
 */

import Testing
import Foundation
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import SwiftAISDK

@Suite("MockLanguageModel Tests")
struct MockLanguageModelTests {

    // MARK: - NotImplemented Tests

    @Test("notImplemented throws error")
    func testNotImplementedThrowsError() async throws {
        #expect(throws: NotImplementedError.self) {
            let _: String = try notImplemented()
        }
    }

    // MARK: - MockLanguageModelV2 Tests

    @Test("MockLanguageModelV2 records doGenerate calls")
    func testMockV2RecordsGenerateCalls() async throws {
        let mock = MockLanguageModelV2(
            doGenerate: .singleValue(LanguageModelV2GenerateResult(
                content: [.text(LanguageModelV2Text(text: "test"))],
                finishReason: .stop,
                usage: LanguageModelV2Usage(inputTokens: 10, outputTokens: 20)
            ))
        )

        #expect(mock.doGenerateCalls.isEmpty)

        let options = LanguageModelV2CallOptions(
            prompt: [.system(content: "System", providerOptions: nil)],
            abortSignal: { false }
        )

        _ = try await mock.doGenerate(options: options)

        #expect(mock.doGenerateCalls.count == 1)
        #expect(mock.doGenerateCalls[0].prompt.count == 1)
    }

    @Test("MockLanguageModelV2 single value mode returns same value")
    func testMockV2SingleValueMode() async throws {
        let result = LanguageModelV2GenerateResult(
            content: [.text(LanguageModelV2Text(text: "test"))],
            finishReason: .stop,
            usage: LanguageModelV2Usage(inputTokens: 10, outputTokens: 20)
        )

        let mock = MockLanguageModelV2(
            doGenerate: .singleValue(result)
        )

        let options = LanguageModelV2CallOptions(
            prompt: [.system(content: "System", providerOptions: nil)],
            abortSignal: { false }
        )

        let result1 = try await mock.doGenerate(options: options)
        let result2 = try await mock.doGenerate(options: options)

        #expect(result1.finishReason == LanguageModelV2FinishReason.stop)
        #expect(result2.finishReason == LanguageModelV2FinishReason.stop)
        #expect(mock.doGenerateCalls.count == 2)
    }

    @Test("MockLanguageModelV2 array mode returns values by index")
    func testMockV2ArrayMode() async throws {
        let result1 = LanguageModelV2GenerateResult(
            content: [.text(LanguageModelV2Text(text: "first"))],
            finishReason: .stop,
            usage: LanguageModelV2Usage(inputTokens: 10, outputTokens: 20)
        )

        let result2 = LanguageModelV2GenerateResult(
            content: [.text(LanguageModelV2Text(text: "second"))],
            finishReason: .length,
            usage: LanguageModelV2Usage(inputTokens: 15, outputTokens: 25)
        )

        let mock = MockLanguageModelV2(
            doGenerate: .array([result1, result2])
        )

        let options = LanguageModelV2CallOptions(
            prompt: [.system(content: "System", providerOptions: nil)],
            abortSignal: { false }
        )

        let firstResult = try await mock.doGenerate(options: options)
        #expect(firstResult.finishReason == LanguageModelV2FinishReason.stop)

        let secondResult = try await mock.doGenerate(options: options)
        #expect(secondResult.finishReason == LanguageModelV2FinishReason.length)
    }

    @Test("MockLanguageModelV2 function mode executes custom logic")
    func testMockV2FunctionMode() async throws {
        var callCount = 0

        let mock = MockLanguageModelV2(
            doGenerate: .function { _ in
                callCount += 1
                return LanguageModelV2GenerateResult(
                    content: [.text(LanguageModelV2Text(text: "call \(callCount)"))],
                    finishReason: .stop,
                    usage: LanguageModelV2Usage(inputTokens: 10, outputTokens: 20)
                )
            }
        )

        let options = LanguageModelV2CallOptions(
            prompt: [.system(content: "System", providerOptions: nil)],
            abortSignal: { false }
        )

        _ = try await mock.doGenerate(options: options)
        _ = try await mock.doGenerate(options: options)

        #expect(callCount == 2)
        #expect(mock.doGenerateCalls.count == 2)
    }

    @Test("MockLanguageModelV2 notImplemented throws by default")
    func testMockV2NotImplementedDefault() async throws {
        let mock = MockLanguageModelV2()

        let options = LanguageModelV2CallOptions(
            prompt: [.system(content: "System", providerOptions: nil)],
            abortSignal: { false }
        )

        await #expect(throws: NotImplementedError.self) {
            try await mock.doGenerate(options: options)
        }
    }

    // MARK: - MockLanguageModelV3 Tests

    @Test("MockLanguageModelV3 records doGenerate calls")
    func testMockV3RecordsGenerateCalls() async throws {
        let mock = MockLanguageModelV3(
            doGenerate: .singleValue(LanguageModelV3GenerateResult(
                content: [.text(LanguageModelV3Text(text: "test"))],
                finishReason: .stop,
                usage: LanguageModelV3Usage(inputTokens: 10, outputTokens: 20)
            ))
        )

        #expect(mock.doGenerateCalls.isEmpty)

        let options = LanguageModelV3CallOptions(
            prompt: [.system(content: "System", providerOptions: nil)],
            abortSignal: { false }
        )

        _ = try await mock.doGenerate(options: options)

        #expect(mock.doGenerateCalls.count == 1)
        #expect(mock.doGenerateCalls[0].prompt.count == 1)
    }

    @Test("MockLanguageModelV3 array mode returns values by index")
    func testMockV3ArrayMode() async throws {
        let result1 = LanguageModelV3GenerateResult(
            content: [.text(LanguageModelV3Text(text: "first"))],
            finishReason: .stop,
            usage: LanguageModelV3Usage(inputTokens: 10, outputTokens: 20)
        )

        let result2 = LanguageModelV3GenerateResult(
            content: [.text(LanguageModelV3Text(text: "second"))],
            finishReason: .length,
            usage: LanguageModelV3Usage(inputTokens: 15, outputTokens: 25)
        )

        let mock = MockLanguageModelV3(
            doGenerate: .array([result1, result2])
        )

        let options = LanguageModelV3CallOptions(
            prompt: [.system(content: "System", providerOptions: nil)],
            abortSignal: { false }
        )

        let firstResult = try await mock.doGenerate(options: options)
        #expect(firstResult.finishReason == LanguageModelV3FinishReason.stop)

        let secondResult = try await mock.doGenerate(options: options)
        #expect(secondResult.finishReason == LanguageModelV3FinishReason.length)
    }

    @Test("MockLanguageModelV3 provider and modelId are configurable")
    func testMockV3Configuration() async throws {
        let mock = MockLanguageModelV3(
            provider: "test-provider",
            modelId: "test-model"
        )

        #expect(mock.provider == "test-provider")
        #expect(mock.modelId == "test-model")
        #expect(mock.specificationVersion == "v3")
    }

    // MARK: - MockValues Tests

    @Test("mockValues returns values sequentially")
    func testMockValuesSequential() throws {
        let values = mockValues(1, 2, 3)

        #expect(values() == 1)
        #expect(values() == 2)
        #expect(values() == 3)
    }

    @Test("mockValues repeats last value when exhausted")
    func testMockValuesRepeatsLast() throws {
        let values = mockValues("a", "b")

        #expect(values() == "a")
        #expect(values() == "b")
        #expect(values() == "b")  // repeats
        #expect(values() == "b")  // repeats
    }

    @Test("mockValues works with single value")
    func testMockValuesSingle() throws {
        let values = mockValues(42)

        #expect(values() == 42)
        #expect(values() == 42)
        #expect(values() == 42)
    }
}
