import ExamplesCore
import Foundation
import SwiftAISDK

@main
struct WeatherToolExample: CLIExample {
    private struct WeatherQuery: Codable, Sendable { let location: String }
    private struct WeatherReport: Codable, Sendable {
        let location: String
        let temperatureFahrenheit: Int
    }

    static let name = "Weather Tool"
    static let description = "Swift port of the weather tool example from Vercel AI SDK."

    static func run() async throws {
        let weatherTool = tool(
            description: "Get the weather in a location",
            inputSchema: WeatherQuery.self,
            execute: { (query, _) in
                WeatherReport(
                    location: query.location,
                    temperatureFahrenheit: Int.random(in: 62...82)
                )
            }
        )

        let result = try await weatherTool.execute?(
            WeatherQuery(location: "San Francisco"),
            ToolCallOptions(toolCallId: "weather-call", messages: [])
        )

        Logger.section("Weather tool output")
        if let report = try await result?.resolve() {
            Helpers.printJSON(report)
        } else {
            Logger.info("No result produced by tool")
        }

        Logger.success("Weather tool example completed")
    }
}
