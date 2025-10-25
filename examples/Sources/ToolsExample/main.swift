import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct WeatherQuery: Codable, Sendable {
    let location: String
}

struct WeatherReport: Codable, Sendable {
    let location: String
    let temperatureFahrenheit: Int
}

struct CityAttractionsQuery: Codable, Sendable {
    let city: String
}

struct CityAttractionsResult: Codable, Sendable {
    let city: String
    let attractions: [String]
}

@main
struct ToolsExample: CLIExample {
    static let name = "Tools / Function Calling"
    static let description = "Use tools to extend model capabilities"

    static func run() async throws {
        try EnvLoader.load()

        let weatherTool = tool(
            description: "Get the weather in a location",
            inputSchema: WeatherQuery.self
        ) { query, _ in
            WeatherReport(
                location: query.location,
                temperatureFahrenheit: Int.random(in: 62...82)
            )
        }

        let cityAttractionsTool = tool(
            description: "Suggest attractions in a city",
            inputSchema: CityAttractionsQuery.self
        ) { query, _ in
            CityAttractionsResult(
                city: query.city,
                attractions: [
                    "Visit the Golden Gate Bridge",
                    "Walk through Golden Gate Park",
                    "Explore the Ferry Building"
                ]
            )
        }

        let tools: ToolSet = [
            "weather": weatherTool.eraseToTool(),
            "cityAttractions": cityAttractionsTool.eraseToTool()
        ]

        Logger.section("Calling tools with generateText")

        let result = try await generateText(
            model: openai("gpt-4o-mini"),
            tools: tools,
            prompt: "What is the weather in San Francisco and which attractions should I visit?"
        )

        Logger.info("Text: \(result.text)")

        if !result.toolCalls.isEmpty {
            Logger.separator()
            Logger.info("Tool calls:")
            for call in result.toolCalls where !call.isDynamic {
                switch call.toolName {
                case "weather":
                    let input = try await weatherTool.decodeInput(from: call)
                    Logger.info("  weather(location: \(input.location))")
                case "cityAttractions":
                    let input = try await cityAttractionsTool.decodeInput(from: call)
                    Logger.info("  cityAttractions(city: \(input.city))")
                default:
                    Logger.info("  \(call.toolName)")
                }
            }
        }

        if !result.toolResults.isEmpty {
            Logger.separator()
            Logger.info("Tool results:")
            for toolResult in result.toolResults where !toolResult.isDynamic {
                switch toolResult.toolName {
                case "weather":
                    let report = try weatherTool.decodeOutput(from: toolResult)
                    Logger.info("  Weather: \(report.temperatureFahrenheit)°F in \(report.location)")
                case "cityAttractions":
                    let attractions = try cityAttractionsTool.decodeOutput(from: toolResult)
                    Logger.info("  Attractions in \(attractions.city): \(attractions.attractions.joined(separator: ", "))")
                default:
                    Logger.info("  \(toolResult.toolName)")
                }
            }
        }
    }
}
