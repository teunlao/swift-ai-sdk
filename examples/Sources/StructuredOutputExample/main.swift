import ExamplesCore
import Foundation
import OpenAIProvider
import SwiftAISDK

@main
struct StructuredOutputExample: CLIExample {
    private struct Summary: Codable, Sendable {
        enum Sentiment: String, Codable, Sendable, CaseIterable { case positive, neutral, negative }
        let summary: String
        let sentiment: Sentiment
    }

    static let name = "Structured Output"
    static let description = "Demonstrates generateText with Output.object schema."

    static func run() async throws {
        try EnvLoader.load()

        Logger.section("Generating structured summary")

        let outputSpec = Output.object(Summary.self)

        do {
            let result: DefaultGenerateTextResult<Summary> = try await generateText(
                model: .v3(openai.responses(modelId: "gpt-4.1-mini")),
                prompt: "Summarize Swift AI SDK and rate the sentiment.",
                experimentalOutput: outputSpec
            )

            let summary = try result.experimentalOutput

            Logger.info("Summary: \(summary.summary)")
            Logger.info("Sentiment: \(summary.sentiment.rawValue)")
            Logger.success("Structured output example completed")
        } catch let error as NoObjectGeneratedError {
            Logger.error("Model text: \(error.text ?? "<nil>")")
            throw error
        }
    }
}
