import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct StreamTextOpenAIAbortExample: Example {
  static let name = "stream-text/openai-abort"
  static let description = "Cancel a streaming request using CallSettings.abortSignal after a timeout."

  static func run() async throws {
    // Abort flag shared with the abortSignal closure
    final class AbortBox { var value = false }
    let abort = AbortBox()

    // Flip the flag after 1s
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 1_000_000_000)
      abort.value = true
    }

    do {
      let stream = try streamText(
        model: openai("gpt-4o"),
        prompt: "Write a short story about a robot learning to love:\n\n",
        onAbort: { _ in Logger.info("aborted") },
        settings: CallSettings(abortSignal: { abort.value })
      )

      // Drain whatever arrives until abort happens
      for try await delta in stream.textStream {
        print(delta, terminator: "")
      }
      print("")
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}

