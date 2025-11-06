import ExamplesCore
import OpenAIProvider
import SwiftAISDK
import Foundation

struct StreamTextOpenAIOutputObjectExample: Example {
  static let name = "stream-text/openai-output-object"
  static let description = "Stream with structured output parsing via Output.object(schema:)."

  private struct Release: Codable, Sendable {
    let name: String
    let version: String
    let changes: [String]
  }

  static func run() async throws {
    do {
      Logger.section("Streaming with Output.object schema")
      let outputSpec = Output.object(Release.self, name: "release", description: "Release notes")

      let result: DefaultStreamTextResult<Release, JSONValue> = try streamText(
        model: openai("gpt-4o"),
        system: nil,
        messages: [.user(UserModelMessage(content: .text("Return a JSON object with name, version, and 3 short changes for 'Swift AI SDK'.")))],
        experimentalOutput: outputSpec,
        onFinish: { finalStep, _, usage, reason in
          Logger.section("onFinish")
          Logger.info("finishReason: \(reason)")
          Logger.info("tokens: \(usage.totalTokens ?? 0)")
        }
      )

      // Drain the text stream to drive the pipeline
      for try await _ in result.textStream { }

      // Access parsed structured output
      do {
        let release = try await result.experimentalOutput
        Logger.section("Parsed Output")
        Logger.info("Release: \(release.name) v\(release.version)")
        for c in release.changes { Logger.info("- \(c)") }
      } catch { Logger.warning("No structured output parsed: \(error.localizedDescription)") }
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}
