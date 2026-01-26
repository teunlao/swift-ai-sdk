import Foundation
import Testing
@testable import AISDKProvider
@testable import OpenAIProvider

@Suite("OpenAIChatPrepareTools")
struct OpenAIChatPrepareToolsTests {
    private func makeFunctionTool(name: String = "testFunction", description: String? = nil, strict: Bool? = nil) -> LanguageModelV3Tool {
        .function(
            LanguageModelV3FunctionTool(
                name: name,
                inputSchema: .object(["type": .string("object")]),
                description: description,
                strict: strict
            )
        )
    }

    private func makeProviderTool(id: String, name: String) -> LanguageModelV3Tool {
        .providerDefined(
            LanguageModelV3ProviderDefinedTool(
                id: id,
                name: name,
                args: [:]
            )
        )
    }

    @Test("no tools yields nil values")
    func noToolsYieldsNil() throws {
        let result = OpenAIChatToolPreparer.prepare(
            tools: [],
            toolChoice: nil
        )

        #expect(result.tools == nil)
        #expect(result.toolChoice == nil)
        #expect(result.warnings.isEmpty)
    }

    @Test("function tool maps to OpenAI function without strict")
    func functionToolWithoutStructuredOutputs() throws {
        let result = OpenAIChatToolPreparer.prepare(
            tools: [makeFunctionTool(description: "A test function")],
            toolChoice: nil
        )

        guard let tools = result.tools, case .array(let array) = tools, array.count == 1 else {
            Issue.record("Expected array with single tool")
            return
        }
        guard case .object(let toolObject) = array.first,
              case .object(let functionObject)? = toolObject["function"] else {
            Issue.record("Expected function object")
            return
        }
        #expect(functionObject["name"] == .string("testFunction"))
        #expect(functionObject["description"] == .string("A test function"))
        #expect(functionObject["strict"] == nil)
        #expect(result.warnings.isEmpty)
    }

    @Test("function tool passes through strict")
    func functionToolWithStrictSetting() throws {
        let result = OpenAIChatToolPreparer.prepare(
            tools: [makeFunctionTool(strict: true)],
            toolChoice: nil
        )

        guard let tools = result.tools, case .array(let array) = tools, array.count == 1 else {
            Issue.record("Expected tool array")
            return
        }
        guard case .object(let toolObject) = array.first,
              case .object(let functionObject)? = toolObject["function"] else {
            Issue.record("Expected function object")
            return
        }
        #expect(functionObject["strict"] == .bool(true))
    }

    @Test("unsupported provider tool produces warning")
    func unsupportedProviderToolProducesWarning() throws {
        let tool = makeProviderTool(id: "openai.unsupported_tool", name: "unsupported")
        let result = OpenAIChatToolPreparer.prepare(
            tools: [tool],
            toolChoice: nil
        )

        #expect(result.tools == .array([]))
        #expect(result.warnings.count == 1)
        if let warning = result.warnings.first {
            if case .unsupportedTool(let reportedTool, _) = warning {
                #expect(reportedTool == tool)
            } else {
                Issue.record("Expected unsupported tool warning")
            }
        }
    }

    @Test("tool choice auto maps to string")
    func toolChoiceAuto() throws {
        let result = OpenAIChatToolPreparer.prepare(
            tools: [makeFunctionTool()],
            toolChoice: .auto
        )

        #expect(result.toolChoice == .string("auto"))
    }

    @Test("tool choice required maps to string")
    func toolChoiceRequired() throws {
        let result = OpenAIChatToolPreparer.prepare(
            tools: [makeFunctionTool()],
            toolChoice: .required
        )

        #expect(result.toolChoice == .string("required"))
    }

    // Port of openai-chat-prepare-tools.test.ts: "should handle tool choice 'none'"
    @Test("tool choice none maps to string")
    func toolChoiceNone() throws {
        let tool = LanguageModelV3Tool.function(
            LanguageModelV3FunctionTool(
                name: "testFunction",
                inputSchema: .object([:]),
                description: "Test"
            )
        )

        let result = OpenAIChatToolPreparer.prepare(
            tools: [tool],
            toolChoice: LanguageModelV3ToolChoice.none
        )

        #expect(result.toolChoice == .string("none"))
    }

    @Test("tool choice for specific function maps to function entry")
    func toolChoiceForFunction() throws {
        let result = OpenAIChatToolPreparer.prepare(
            tools: [makeFunctionTool(name: "lookup")],
            toolChoice: .tool(toolName: "lookup")
        )

        #expect(result.toolChoice == .object([
            "type": .string("function"),
            "function": .object(["name": .string("lookup")])
        ]))
    }
}
