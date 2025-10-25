import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct Release: Codable, Sendable {
    let name: String
    let version: String
    let changes: [String]
}

@main
struct READMEExamples: CLIExample {
    static let name = "README Structured Output"
    static let description = "Validates the README generateObject snippet."

    static func run() async throws {
        try EnvLoader.load()

        Logger.section("Running README generateObject snippet")

        let result = try await generateObject(
            model: openai("gpt-5-mini"),
            schema: Release.self,
            prompt: "Summarize Swift AI SDK 0.1.0: streaming + tools.",
            schemaName: "release_summary"
        ).object

        Logger.info("Release: \(result.name) (\(result.version))")
        Logger.info("Changes:")
        for change in result.changes {
            Logger.info("- \(change)")
        }

        Logger.success("README structured output example completed")
    }
}
