/**
 Testing Example

 Demonstrates mock providers and test helpers in AI SDK.
 Corresponds to: apps/docs/src/content/docs/ai-sdk-core/testing.mdx
 */

import Foundation
import SwiftAISDK
import AISDKProvider
import AISDKProviderUtils
import ExamplesCore

@main
struct TestingExample: CLIExample {
  static let name = "Testing"
  static let description = "Mock providers and test helpers"

  static func run() async throws {
    // Example 1: generateText with Mock
    Logger.section("Example 1: generateText with Mock")
    Logger.info("Using MockLanguageModelV3 to simulate text generation...")

    let mockModel1 = MockLanguageModelV3(
      doGenerate: .function { _ in
        LanguageModelV3GenerateResult(
          content: [.text(LanguageModelV3Text(text: "Hello, world!"))],
          finishReason: .stop,
          usage: LanguageModelV3Usage(
            inputTokens: 10,
            outputTokens: 20
          )
        )
      }
    )

    let result1 = try await generateText(
      model: mockModel1,
      prompt: "Hello, test!"
    )

    Logger.info("✅ Generated text: \(result1.text)")
    Logger.info("   Usage: \(result1.usage.inputTokens ?? 0) input + \(result1.usage.outputTokens ?? 0) output tokens")

    // Example 2: streamText with Mock
    Logger.section("Example 2: streamText with Mock")
    Logger.info("Using MockLanguageModelV3 to simulate streaming...")

    let mockModel2 = MockLanguageModelV3(
      doStream: .function { _ in
        LanguageModelV3StreamResult(
          stream: simulateReadableStream(
            chunks: [
              .textStart(id: "text-1", providerMetadata: nil),
              .textDelta(id: "text-1", delta: "Hello", providerMetadata: nil),
              .textDelta(id: "text-1", delta: ", ", providerMetadata: nil),
              .textDelta(id: "text-1", delta: "world!", providerMetadata: nil),
              .textEnd(id: "text-1", providerMetadata: nil),
              .finish(
                finishReason: .stop,
                usage: LanguageModelV3Usage(
                  inputTokens: 3,
                  outputTokens: 10
                ),
                providerMetadata: nil
              )
            ]
          )
        )
      }
    )

    let result2 = try await streamText(
      model: mockModel2,
      prompt: "Hello, test!"
    )

    Logger.info("Streaming:")
    for try await textPart in result2.textStream {
      print(textPart, terminator: "")
      fflush(stdout)
    }
    print()
    Logger.info("✅ Stream complete")

    // Example 3: Recording Calls
    Logger.section("Example 3: Recording Calls")
    Logger.info("MockLanguageModelV3 records all calls for verification...")

    let mockModel3 = MockLanguageModelV3(
      doGenerate: .function { _ in
        LanguageModelV3GenerateResult(
          content: [.text(LanguageModelV3Text(text: "Response"))],
          finishReason: .stop,
          usage: LanguageModelV3Usage(inputTokens: 5, outputTokens: 5)
        )
      }
    )

    // Make multiple calls
    _ = try await generateText(model: mockModel3, prompt: "First call")
    _ = try await generateText(model: mockModel3, prompt: "Second call")

    // Check recorded calls
    Logger.info("Total doGenerate calls: \(mockModel3.doGenerateCalls.count)")
    for (index, _) in mockModel3.doGenerateCalls.enumerated() {
      Logger.info("  Call \(index + 1) recorded")
    }
    Logger.info("✅ Call recording verified")

    // Example 4: Different Finish Reasons
    Logger.section("Example 4: Different Finish Reasons")
    Logger.info("Simulating different completion scenarios...")

    let stopModel = MockLanguageModelV3(
      doGenerate: .function { _ in
        LanguageModelV3GenerateResult(
          content: [.text(LanguageModelV3Text(text: "Complete"))],
          finishReason: .stop,
          usage: LanguageModelV3Usage(inputTokens: 3, outputTokens: 2)
        )
      }
    )

    let lengthModel = MockLanguageModelV3(
      doGenerate: .function { _ in
        LanguageModelV3GenerateResult(
          content: [.text(LanguageModelV3Text(text: "Truncated..."))],
          finishReason: .length,
          usage: LanguageModelV3Usage(inputTokens: 3, outputTokens: 100)
        )
      }
    )

    let stopResult = try await generateText(model: stopModel, prompt: "Test")
    Logger.info("Stop model: \(stopResult.finishReason)")

    let lengthResult = try await generateText(model: lengthModel, prompt: "Test")
    Logger.info("Length model: \(lengthResult.finishReason)")

    Logger.info("✅ Finish reasons tested")

    // Example 5: mockValues Helper
    Logger.section("Example 5: mockValues Helper")
    Logger.info("Using mockValues to return different responses per call...")

    let mockResponses = mockValues(
      LanguageModelV3GenerateResult(
        content: [.text(LanguageModelV3Text(text: "First response"))],
        finishReason: .stop,
        usage: LanguageModelV3Usage(inputTokens: 10, outputTokens: 5)
      ),
      LanguageModelV3GenerateResult(
        content: [.text(LanguageModelV3Text(text: "Second response"))],
        finishReason: .stop,
        usage: LanguageModelV3Usage(inputTokens: 10, outputTokens: 5)
      )
    )

    let mockModel5 = MockLanguageModelV3(
      doGenerate: .function { _ in mockResponses() }
    )

    // First call
    let call1 = try await generateText(model: mockModel5, prompt: "Test 1")
    Logger.info("Call 1: \(call1.text)")

    // Second call
    let call2 = try await generateText(model: mockModel5, prompt: "Test 2")
    Logger.info("Call 2: \(call2.text)")

    // Third call - repeats last value
    let call3 = try await generateText(model: mockModel5, prompt: "Test 3")
    Logger.info("Call 3: \(call3.text) (repeats last)")

    Logger.info("✅ mockValues worked as expected")

    // Example 6: Simulating Delays
    Logger.section("Example 6: Simulating Delays")
    Logger.info("Using simulateReadableStream with delays...")

    let mockModel6 = MockLanguageModelV3(
      doStream: .function { _ in
        LanguageModelV3StreamResult(
          stream: simulateReadableStream(
            chunks: [
              .textStart(id: "text-1", providerMetadata: nil),
              .textDelta(id: "text-1", delta: "Slow", providerMetadata: nil),
              .textDelta(id: "text-1", delta: " stream", providerMetadata: nil),
              .textEnd(id: "text-1", providerMetadata: nil),
              .finish(
                finishReason: .stop,
                usage: LanguageModelV3Usage(inputTokens: 3, outputTokens: 2),
                providerMetadata: nil
              )
            ],
            initialDelayInMs: 500,  // Wait 500ms before first chunk
            chunkDelayInMs: 200      // Wait 200ms between chunks
          )
        )
      }
    )

    let result6 = try await streamText(
      model: mockModel6,
      prompt: "Hello"
    )

    Logger.info("Streaming with delays:")
    let startTime = Date()
    for try await textPart in result6.textStream {
      let elapsed = Date().timeIntervalSince(startTime)
      print("[\(String(format: "%.1f", elapsed))s] \(textPart)", terminator: "")
      fflush(stdout)
    }
    print()
    Logger.info("✅ Delayed stream complete")

    // Summary
    Logger.separator()
    Logger.info("Testing examples complete!")
    Logger.info("Key concepts:")
    Logger.info("  • MockLanguageModelV3 for controllable test behavior")
    Logger.info("  • simulateReadableStream for streaming tests")
    Logger.info("  • mockValues for multi-call scenarios")
    Logger.info("  • Delays for realistic timing tests")
    Logger.info("  • No real API calls - fast, deterministic, free!")
  }
}
