/**
 Error Handling Example

 Demonstrates error handling in AI SDK.
 Corresponds to: apps/docs/src/content/docs/ai-sdk-core/error-handling.mdx
 */

import Foundation
import SwiftAISDK
import OpenAIProvider
import AISDKProvider
import ExamplesCore

@main
struct ErrorHandlingExample: CLIExample {
  static let name = "Error Handling"
  static let description = "Handle errors gracefully in AI SDK"

  static func run() async throws {
    // Example 1: Catching Invalid Model Error
    Logger.section("Example 1: Catching Invalid Model Error")
    Logger.info("Attempting to use non-existent model...")

    do {
      let result = try await generateText(
        model: openai("gpt-99-nonexistent-model"),
        prompt: "Say hello"
      )
      Logger.info("❌ Should not reach here: \(result.text)")
    } catch let error as APICallError {
      Logger.info("✅ Caught APICallError as expected")
      Logger.info("   Message: \(error.message)")
      Logger.info("   Status: \(error.statusCode ?? 0)")
    } catch {
      Logger.info("❌ Unexpected error type: \(error)")
    }

    // Example 2: Streaming Error with Invalid Model
    Logger.section("Example 2: Streaming Error with Invalid Model")
    Logger.info("Attempting to stream with invalid model...")

    do {
      let result = try await streamText(
        model: openai("invalid-stream-model-xyz"),
        prompt: "Count from 1 to 5"
      )

      Logger.info("❌ Should not reach streaming loop")
      for try await textPart in result.textStream {
        print(textPart, terminator: "")
      }
    } catch let error as APICallError {
      Logger.info("✅ Caught APICallError during streaming")
      Logger.info("   Message: \(error.message)")
    } catch {
      Logger.info("❌ Unexpected error: \(error)")
    }

    // Example 3: Full Stream (showing error/abort handlers)
    Logger.section("Example 3: Full Stream with Error Handlers")
    Logger.info("Demonstrating error/abort/toolError handlers in fullStream...")
    Logger.info("(This example completes successfully, but handlers are ready)")

    do {
      let result = try await streamText(
        model: openai("gpt-4o"),
        prompt: "Count to 3"
      )

      for try await part in result.fullStream {
        switch part {
        case .textDelta(_, let delta, _):
          print(delta, terminator: "")
          fflush(stdout)

        case .error(let error):
          Logger.info("\n❌ Stream error would be caught here: \(error)")

        case .abort:
          Logger.info("\n⚠️  Stream abort would be caught here")

        case .toolError(let error):
          Logger.info("\n❌ Tool error would be caught here: \(error)")

        default:
          break
        }
      }
      print()
      Logger.info("✅ Stream completed without errors")
    } catch {
      Logger.info("❌ Error outside stream: \(error)")
    }

    // Example 4: onAbort Callback (demonstrates handler setup)
    Logger.section("Example 4: onAbort Callback")
    Logger.info("Setting up onAbort callback (stream completes normally here)...")

    var abortCalled = false

    let result = try await streamText(
      model: openai("gpt-4o"),
      prompt: "Count to 5",
      onFinish: { _, _, _, _ in
        Logger.info("✅ onFinish called (normal completion)")
      },
      onAbort: { steps in
        abortCalled = true
        Logger.info("⚠️  onAbort would be called if stream was aborted")
        Logger.info("    Steps completed: \(steps.count)")
      }
    )

    Logger.info("Streaming:")
    for try await textPart in result.textStream {
      print(textPart, terminator: "")
      fflush(stdout)
    }
    print()

    Logger.info("Abort called: \(abortCalled) (false = normal completion)")
    Logger.info("Note: onAbort is called only when stream is aborted externally")

    // Example 5: Specific Error Type Handling
    Logger.section("Example 5: Specific Error Types")
    Logger.info("Handling specific error types...")

    // Test with valid call (demonstrate no error)
    Logger.info("\nTest 1: Valid call (should succeed)")
    do {
      let result = try await generateText(
        model: openai("gpt-4o"),
        prompt: "Say hello"
      )
      Logger.info("✅ Success: \(result.text)")
    } catch {
      Logger.info("❌ Unexpected error: \(error)")
    }

    // Empty prompt
    Logger.info("\nTest 2: Empty prompt")
    do {
      _ = try await generateText(
        model: openai("gpt-4o"),
        prompt: ""  // Empty
      )
    } catch let error as InvalidPromptError {
      Logger.info("✅ Caught InvalidPromptError: \(error.message)")
    } catch {
      Logger.info("Note: Empty prompt handled gracefully")
    }

    // API Error simulation
    Logger.info("\nTest 3: Invalid model ID")
    do {
      _ = try await generateText(
        model: openai("invalid-model-id-12345"),
        prompt: "Hello"
      )
    } catch let error as APICallError {
      Logger.info("✅ Caught APICallError")
      Logger.info("   Message: \(error.message)")
      if let statusCode = error.statusCode {
        Logger.info("   Status code: \(statusCode)")
      }
    } catch {
      Logger.info("Note: \(type(of: error)): \(error)")
    }

    // Summary
    Logger.separator()
    Logger.info("Error handling examples complete!")
    Logger.info("Key concepts:")
    Logger.info("  • do-catch blocks for synchronous errors")
    Logger.info("  • textStream error handling")
    Logger.info("  • fullStream with error/abort/toolError parts")
    Logger.info("  • onAbort callback for cleanup")
    Logger.info("  • Specific error type matching")
    Logger.info("  • APICallError, InvalidArgumentError, InvalidPromptError")
  }
}
