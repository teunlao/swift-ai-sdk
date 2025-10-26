import ExamplesCore
import Foundation
import OpenAIProvider
import SwiftAISDK

struct GenerateTextOpenAITimeoutExample: Example {
  static let name = "generate-text/openai-timeout"
  static let description = "Cancels a request using CallSettings.abortSignal after a 1s timeout." 

  static func run() async throws {
    let requestTask = Task {
      try await generateText(
        model: openai("gpt-4o-mini"),
        prompt: "Invent a new holiday and describe its traditions.",
        settings: CallSettings(abortSignal: { Task.isCancelled })
      )
    }

    let timeoutTask = Task {
      try await Task.sleep(nanoseconds: 1_000_000_000)
      Logger.info("Timeout reached, cancelling request...")
      requestTask.cancel()
    }

    defer { timeoutTask.cancel() }

    do {
      let result = try await requestTask.value

      Logger.section("Assistant Text")
      Logger.info(result.text)

      Logger.section("Usage")
      Logger.info(String(describing: result.usage))
    } catch is CancellationError {
      Logger.warning("Request cancelled before completion")
    } catch {
      Logger.warning("Request failed: \(error.localizedDescription)")
    }
  }
}
