import ExamplesCore
import OpenAIProvider
import SwiftAISDK
import Foundation

struct StreamTextOpenAIToolOutputStreamExample: Example {
  static let name = "stream-text/openai-tool-output-stream"
  static let description = "Tool returns a streaming output; observe preliminary tool results in onChunk."

  private struct SynonymsInput: Codable, Sendable { let word: String }

  static func run() async throws {
    do {
      // Streaming tool: yields multiple strings over time.
      let synStream: TypedTool<SynonymsInput, String> = tool(
        description: "Stream synonyms for a given word (one per chunk)",
        inputSchema: .auto(SynonymsInput.self),
        outputSchema: nil,
        needsApproval: nil,
        onInputStart: nil,
        onInputDelta: nil,
        onInputAvailable: nil,
        execute: { (input, _) in
          let words = ["quick", "rapid", "speedy", "agile", "nimble"]
          let stream = AsyncThrowingStream<String, Error> { continuation in
            let task = Task {
              for w in words {
                try? await Task.sleep(nanoseconds: 120_000_000)
                continuation.yield(w)
              }
              continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
          }
          return .stream(stream)
        }
      )

      Logger.section("Streaming tool output via onChunk")
      let result = try streamText(
        model: openai("gpt-4o"),
        prompt: "Use the synStream tool to stream 3-5 synonyms for the word 'swift' and summarize.",
        tools: ["synStream": synStream.tool],
        onChunk: { part in
          switch part {
          case .toolResult(let res):
            let prelim = res.preliminary ?? false
            Logger.info("toolResult prelim=\(prelim) id=\(res.toolCallId) output=\(res.output)")
          default:
            break
          }
        },
        onFinish: { _, _, usage, reason in
          Logger.section("Finish")
          Logger.info("finishReason: \(reason)")
          Logger.info("totalTokens: \(usage.totalTokens ?? 0)")
        }
      )

      for try await delta in result.textStream { print(delta, terminator: "") }
      print("")
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}

