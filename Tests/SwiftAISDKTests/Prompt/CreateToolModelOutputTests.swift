import Testing
import Foundation
import AISDKProvider
import AISDKProviderUtils
@testable import SwiftAISDK

/// Port of `@ai-sdk/ai/src/prompt/create-tool-model-output.test.ts`.
@Suite("createToolModelOutput")
struct CreateToolModelOutputTests {
    private func makeTool(
        toModelOutput: (@Sendable (ToolModelOutputOptions) async throws -> ToolResultOutput)?
    ) -> Tool {
        Tool(
            inputSchema: FlexibleSchema(jsonSchema(.object(["type": .string("object")]))),
            toModelOutput: toModelOutput
        )
    }

    @Test("text error mode returns the error message")
    func errorText() async throws {
        let result = try await createToolModelOutput(
            toolCallId: "1", input: .null, output: "Error message", tool: nil, errorMode: .text
        )
        #expect(result == .errorText(value: "Error message"))
    }

    @Test("json error mode returns the error value and null for a missing output")
    func errorJSON() async throws {
        let result = try await createToolModelOutput(
            toolCallId: "1", input: .null, output: JSONValue.object(["code": .number(500)]), tool: nil, errorMode: .json
        )
        #expect(result == .errorJson(value: .object(["code": .number(500)])))

        let missing = try await createToolModelOutput(
            toolCallId: "1", input: .null, output: nil, tool: nil, errorMode: .json
        )
        #expect(missing == .errorJson(value: .null))
    }

    @Test("toModelOutput receives the tool call id, input and output")
    func usesToModelOutput() async throws {
        let tool = makeTool { options in
            .json(value: .array([.string(options.toolCallId), options.input, options.output]))
        }

        let result = try await createToolModelOutput(
            toolCallId: "call-1",
            input: .object(["city": .string("Paris")]),
            output: JSONValue.string("sunny"),
            tool: tool,
            errorMode: .none
        )

        #expect(result == .json(value: .array([
            .string("call-1"), .object(["city": .string("Paris")]), .string("sunny"),
        ])))
    }

    @Test("error mode takes precedence over toModelOutput")
    func errorModeWins() async throws {
        let tool = makeTool { _ in .text(value: "not used") }
        let result = try await createToolModelOutput(
            toolCallId: "1", input: .null, output: "Error occurred", tool: tool, errorMode: .text
        )
        #expect(result == .errorText(value: "Error occurred"))
    }

    @Test("without toModelOutput a string becomes text and other values become json")
    func defaultMapping() async throws {
        let text = try await createToolModelOutput(
            toolCallId: "1", input: .null, output: JSONValue.string("plain"), tool: makeTool(toModelOutput: nil), errorMode: .none
        )
        #expect(text == .text(value: "plain"))

        let json = try await createToolModelOutput(
            toolCallId: "1", input: .null, output: JSONValue.number(42), tool: nil, errorMode: .none
        )
        #expect(json == .json(value: .number(42)))

        let missing = try await createToolModelOutput(
            toolCallId: "1", input: .null, output: nil, tool: nil, errorMode: .none
        )
        #expect(missing == .json(value: .null))
    }
}
