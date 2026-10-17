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

        let options = ToolExecutionOptions(toolCallId: "weather", messages: [])
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

        let options = ToolExecutionOptions(toolCallId: "stream", messages: [])
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

        let options = ToolExecutionOptions(toolCallId: "cmd", messages: [])
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

    private func toolCallModel(input: String, toolName: String = "weather") -> MockLanguageModelV4 {
        let usage = LanguageModelV4Usage(inputTokens: .init(total: 1), outputTokens: .init(total: 1))
        return MockLanguageModelV4(doGenerate: .array([
            LanguageModelV4GenerateResult(
                content: [.toolCall(LanguageModelV4ToolCall(toolCallId: "call-1", toolName: toolName, input: input))],
                finishReason: LanguageModelV4FinishReason(unified: .toolCalls),
                usage: usage
            ),
            LanguageModelV4GenerateResult(
                content: [.text(LanguageModelV4Text(text: "done"))],
                finishReason: LanguageModelV4FinishReason(unified: .stop),
                usage: usage
            )
        ]))
    }

    @Test("a typed tool returning a scalar produces that scalar as its result")
    func scalarOutputThroughGenerateText() async throws {
        let model = toolCallModel(input: #"{"location":"Paris"}"#)
        let weather = tool(inputSchema: WeatherQuery.self, execute: { (query: WeatherQuery, _) async throws -> String in
            "Sunny in \(query.location)"
        })

        let result = try await generateText(
            model: model,
            tools: ["weather": weather.tool],
            prompt: "weather?",
            stopWhen: [isStepCount(2)]
        )

        #expect(result.steps.first?.toolResults.map(\.output) == [.string("Sunny in Paris")])
        let secondPrompt = model.doGenerateCalls.last?.prompt ?? []
        let toolOutputs = secondPrompt.flatMap { message -> [LanguageModelV4ToolResultOutput] in
            guard case .tool(let content, _) = message else { return [] }
            return content.compactMap { part in
                if case .toolResult(let result) = part { return result.output }
                return nil
            }
        }
        #expect(toolOutputs == [.text(value: "Sunny in Paris")])
    }

    @Test("an input the typed schema rejects goes to tool-call repair")
    func invalidTypedInputIsRepaired() async throws {
        let model = toolCallModel(input: #"{"city":"Paris"}"#)
        let executed = LockedInputs()
        let weather = tool(inputSchema: WeatherQuery.self, execute: { (query: WeatherQuery, _) async throws -> String in
            executed.append(query.location)
            return "Sunny"
        })

        let result = try await generateText(
            model: model,
            tools: ["weather": weather.tool],
            prompt: "weather?",
            stopWhen: [isStepCount(2)],
            repairToolCall: { options in
                LanguageModelV4ToolCall(
                    toolCallId: options.toolCall.toolCallId,
                    toolName: options.toolCall.toolName,
                    input: #"{"location":"Paris"}"#
                )
            }
        )

        #expect(result.steps.first?.toolCalls.first?.invalid != true)
        #expect(executed.values == ["Paris"])
    }

    @Test("callbacks, the recorded call and execute see the input the typed schema produced")
    func transformedInputIsShared() async throws {
        let trimmed = FlexibleSchema<WeatherQuery>(Schema(
            jsonSchemaResolver: { ["type": "object", "properties": ["location": ["type": "string"]]] },
            validator: { value in
                guard let object = value as? [String: Any], let location = object["location"] as? String else {
                    return .failure(error: TypeValidationError.wrap(value: value, cause: CancellationError()))
                }
                return .success(value: WeatherQuery(location: location.trimmingCharacters(in: .whitespaces)))
            }
        ))
        let model = toolCallModel(input: #"{"location":"  Paris  "}"#)
        let seen = LockedInputs()
        let weather = tool(
            inputSchema: trimmed,
            onInputAvailable: { options in seen.append("callback:\(options.input)") },
            execute: { (query: WeatherQuery, _) async throws -> String in
                seen.append("execute:\(query.location)")
                return "Sunny"
            }
        )

        let result = try await generateText(
            model: model,
            tools: ["weather": weather.tool],
            prompt: "weather?",
            stopWhen: [isStepCount(2)]
        )

        let expectedInput: JSONValue = ["location": "Paris"]
        #expect(result.steps.first?.toolCalls.first?.input == expectedInput)
        #expect(seen.values == ["callback:\(expectedInput)", "execute:Paris"])
    }

    @Test("toModelOutput receives the tool call id with typed input and output")
    func toModelOutputReceivesTypedCall() async throws {
        let weatherTool = tool(
            inputSchema: WeatherQuery.self,
            outputSchema: FlexibleSchema.auto(WeatherReport.self),
            execute: { (query: WeatherQuery, _) async throws -> WeatherReport in
                WeatherReport(location: query.location, condition: "Sunny")
            },
            toModelOutput: { options in
                .text(value: "\(options.toolCallId):\(options.input.location):\(options.output.condition)")
            }
        )

        let modelOutput = try await createToolModelOutput(
            toolCallId: "call-1",
            input: ["location": .string("Paris")],
            output: JSONValue.object(["location": .string("Paris"), "condition": .string("Sunny")]),
            tool: weatherTool.tool,
            errorMode: .none
        )

        #expect(modelOutput == .text(value: "call-1:Paris:Sunny"))
    }
}

private final class LockedInputs: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []

    var values: [String] { lock.withLock { stored } }

    func append(_ value: String) { lock.withLock { stored.append(value) } }
}
