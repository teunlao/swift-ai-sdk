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
            inputSchema: .auto(WeatherQuery.self),
            execute: { (query, _) in
                WeatherReport(
                    location: query.location,
                    temperatureFahrenheit: Int.random(in: 62...82)
                )
            }
        )


        guard let execute = weatherTool.execute else {
            fatalError("tool missing execute closure")
        }

        let options = ToolCallOptions(toolCallId: "weather-call", messages: [])
        let report = try await execute(WeatherQuery(location: "San Francisco"), options).resolve()

        // Logger.section("Weather tool output")
        // Helpers.printJSON(report)
        // Logger.success("Weather tool example completed")
    }
}
