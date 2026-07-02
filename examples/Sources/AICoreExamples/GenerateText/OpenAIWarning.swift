import ExamplesCore
import Foundation
import OpenAIProvider
import SwiftAISDK

struct GenerateTextOpenAIWarningExample: Example {
  static let name = "generate-text/openai-warning"
  static let description = "Captures provider warnings (e.g. unsupported settings) via AI_SDK_LOG_WARNINGS and result.warnings." 

  static func run() async throws {
    let previousLogger = AI_SDK_LOG_WARNINGS
    let handler: LogWarningsFunction = { warnings in
      let messages = warnings.map(Self.describeWarning).joined(separator: "\n  • ")
      Logger.warning("Warnings logged by SDK:\n  • \(messages)")
    }
    AI_SDK_LOG_WARNINGS = handler
    defer { AI_SDK_LOG_WARNINGS = previousLogger }

    do {
      let result = try await generateText(
        model: openai("gpt-4o-mini"),
        prompt: "Invent a new holiday and describe its traditions.",
        settings: CallSettings(seed: 123)
      )

      Logger.section("Assistant Text")
      Logger.info(result.text)

      Logger.section("Warnings from Result")
      if let warnings = result.warnings, !warnings.isEmpty {
        for warning in warnings {
          Logger.info(Self.describeCallWarning(warning))
        }
      } else {
        Logger.info("No warnings returned by provider.")
      }
    } catch {
      Logger.warning("Request failed: \(error.localizedDescription)")
    }
  }

  private static func describeWarning(_ warning: Warning) -> String {
    switch warning {
    case .languageModel(let w):
      return describeLanguageWarning(w)
    case .embeddingModel(let w):
      return "Embedding model warning: \(describeLanguageWarning(w))"
    case .imageModel(let w):
      return "Image model warning: \(describeLanguageWarning(w))"
    case .videoModel(let w):
      return "Video model warning: \(describeLanguageWarning(w))"
    case .speechModel(let w):
      return "Speech model warning: \(describeLanguageWarning(w))"
    case .transcriptionModel(let w):
      return "Transcription warning: \(describeLanguageWarning(w))"
    case .rerankingModel(let w):
      return "Reranking model warning: \(describeLanguageWarning(w))"
    }
  }

  private static func describeCallWarning(_ warning: CallWarning) -> String {
    return "Language model warning: \(describeLanguageWarning(warning))"
  }

  private static func describeLanguageWarning(_ warning: CallWarning) -> String {
    switch warning {
    case .unsupported(let feature, let details):
      if let details { return "Unsupported feature \(feature): \(details)" }
      return "Unsupported feature \(feature)"
    case .compatibility(let feature, let details):
      if let details { return "Compatibility warning \(feature): \(details)" }
      return "Compatibility warning \(feature)"
    case .deprecated(let setting, let message):
      return "Deprecated setting \(setting): \(message)"
    case .other(let message):
      return message
    }
  }
}
