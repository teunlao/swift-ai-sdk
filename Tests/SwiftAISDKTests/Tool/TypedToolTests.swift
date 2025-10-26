import Foundation
import Testing
@testable import SwiftAISDK

@Suite("Typed Tool")
struct TypedToolTests {
    private struct WeatherQuery: Codable, Equatable, Sendable {
        let location: String
    }

    private struct WeatherReport: Codable, Equatable, Sendable {
        let location: String
        let condition: String
    }

    @Test("executes tool with Codable input/output")
    func executesWithCodableValues() async throws {
        let weatherTool = tool(description: "Weather", inputSchema: WeatherQuery.self, execute: { (query, _) in
            WeatherReport(location: query.location, condition: "Sunny")
        })

        guard let execute = weatherTool.execute else {
            Issue.record("Tool is missing execute closure")
            return
        }

        let options = ToolCallOptions(toolCallId: "weather", messages: [])
        let report = try await execute(WeatherQuery(location: "Paris"), options).resolve()

        #expect(report == WeatherReport(location: "Paris", condition: "Sunny"))

        let helperDecoded = try weatherTool.decodeOutput(from: ["location": .string("Paris"), "condition": .string("Sunny")])
        #expect(helperDecoded == WeatherReport(location: "Paris", condition: "Sunny"))

        let schemaJSON = try await weatherTool.tool.inputSchema.resolve().jsonSchema()
        guard case .object(let schemaRoot) = schemaJSON,
              case .object(let properties) = schemaRoot["properties"],
              case .object(let locationSchema) = properties["location"],
              case .string(let type) = locationSchema["type"] else {
            Issue.record("Unexpected schema: \(schemaJSON)")
            return
        }

        #expect(type == "string")
    }

    @Test("preserves streaming outputs")
    func mapsStreamingOutputs() async throws {
        let tool = tool(description: "Stream", inputSchema: WeatherQuery.self, execute: { (_: WeatherQuery, _) in
            ToolExecutionResult.stream(AsyncThrowingStream { continuation in
                let reports = [
                    WeatherReport(location: "Paris", condition: "Sunny"),
                    WeatherReport(location: "Berlin", condition: "Cloudy"),
                    WeatherReport(location: "Tokyo", condition: "Rain")
                ]

                for report in reports {
                    continuation.yield(report)
                }
                continuation.finish()
            })
        })

        guard let execute = tool.execute else {
            Issue.record("Tool is missing execute closure")
            return
        }

        let options = ToolCallOptions(toolCallId: "stream", messages: [])
        let result = try await execute(WeatherQuery(location: "Anywhere"), options)
        var decodedReports: [WeatherReport] = []

        for try await value in result.asAsyncStream() {
            decodedReports.append(value)
            let json: JSONValue = ["location": .string(value.location), "condition": .string(value.condition)]
            let decoded = try tool.decodeOutput(from: json)
            #expect(decoded == value)
        }

        #expect(decodedReports.count == 3)
        #expect(decodedReports.first?.condition == "Sunny")
        #expect(decodedReports.last?.location == "Tokyo")
    }

    @Test("dynamicTool bridges Codable input/output while remaining dynamic")
    func dynamicToolWithCodableValues() async throws {
        struct Command: Codable, Equatable, Sendable { let action: String }
        struct CommandResult: Codable, Equatable, Sendable { let status: String }

        let tool = dynamicTool(
            description: "Command",
            inputSchema: Command.self,
            needsApproval: .always
        ) { command, _ in
            CommandResult(status: "executed \(command.action)")
        }

        #expect(tool.type == .dynamic)
        switch tool.needsApproval {
        case .always?: break
        default: Issue.record("Expected .always needsApproval")
        }

        guard let execute = tool.execute else {
            Issue.record("Dynamic tool is missing execute closure")
            return
        }

        let options = ToolCallOptions(toolCallId: "cmd", messages: [])
        let result = try await execute(["action": .string("jump")], options).resolve()

        guard case let .object(payload) = result,
              let status = payload["status"],
              status == .string("executed jump") else {
            Issue.record("Unexpected dynamic tool output: \(result)")
            return
        }

        let schemaJSON = try await tool.inputSchema.resolve().jsonSchema()
        guard case let .object(root) = schemaJSON,
              case let .object(properties) = root["properties"],
              case let .object(actionSchema) = properties["action"],
              case let .string(type) = actionSchema["type"] else {
            Issue.record("Unexpected schema: \(schemaJSON)")
            return
        }

        #expect(type == "string")
    }
}
