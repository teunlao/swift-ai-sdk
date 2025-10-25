import ExamplesCore
import Foundation
import SwiftAISDK

private struct WeatherRequest: Codable, Sendable {
    let location: String
}

private struct WeatherResponse: Sendable {
    let location: String
    let temperatureCelsius: Int
}

private enum WeatherToolError: LocalizedError {
    case invalidInput

    var errorDescription: String? {
        switch self {
        case .invalidInput:
            return "Tool input must contain a location string."
        }
    }
}

private func decodeJSONValue<T: Decodable>(_ type: T.Type, from value: JSONValue) throws -> T {
    let foundation = try value.toFoundationObject()

    guard JSONSerialization.isValidJSONObject(foundation) else {
        throw WeatherToolError.invalidInput
    }

    let data = try JSONSerialization.data(withJSONObject: foundation)
    let decoder = JSONDecoder()
    return try decoder.decode(T.self, from: data)
}

private extension JSONValue {
    func toFoundationObject() throws -> Any {
        switch self {
        case .null:
            return NSNull()
        case .bool(let value):
            return value
        case .number(let value):
            return value
        case .string(let value):
            return value
        case .array(let array):
            return try array.map { try $0.toFoundationObject() }
        case .object(let dictionary):
            var result: [String: Any] = [:]
            result.reserveCapacity(dictionary.count)
            for (key, value) in dictionary {
                result[key] = try value.toFoundationObject()
            }
            return result
        }
    }
}

@main
struct WeatherToolExample: CLIExample {
    static let name = "Weather Tool"
    static let description = "Swift port of the weather tool example from Vercel AI SDK."

    static func run() async throws {
        Logger.section("Creating weather tool")

        let codableSchema = FlexibleSchema.auto(WeatherRequest.self)
        let jsonSchemaValue = try await codableSchema.resolve().jsonSchema()
        let toolSchema = FlexibleSchema<JSONValue>(jsonSchema(jsonSchemaValue))

        let weatherTool = tool(
            description: "Get the weather in a location",
            inputSchema: toolSchema,
            execute: { input, _ in
                let request = try decodeJSONValue(WeatherRequest.self, from: input)
                let response = WeatherResponse(
                    location: request.location,
                    temperatureCelsius: Int.random(in: 15...30)
                )

                let payload: JSONValue = .object([
                    "location": .string(response.location),
                    "temperatureCelsius": .number(Double(response.temperatureCelsius))
                ])

                return .value(payload)
            }
        )

        Logger.section("Executing tool locally")

        guard let execute = weatherTool.execute else {
            throw WeatherToolError.invalidInput
        }

        let options = ToolCallOptions(
            toolCallId: "weather-call-1",
            messages: []
        )

        let stream = executeTool(
            execute: execute,
            input: JSONValue.object(["location": .string("San Francisco")]),
            options: options
        )

        var finalResult: JSONValue?
        for try await chunk in stream {
            switch chunk {
            case .preliminary(let value):
                Logger.info("Partial result: \(value)")
            case .final(let value):
                finalResult = value
                Logger.success("Final result received")
            }
        }

        if let finalResult {
            Logger.separator()
            Logger.info("Weather tool output:")
            Helpers.printJSON(finalResult)
        }

        Logger.separator()
        Logger.success("Weather tool example completed")
    }
}
