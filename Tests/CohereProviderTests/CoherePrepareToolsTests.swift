import Foundation
import Testing
@testable import AISDKProvider
@testable import CohereProvider

@Suite("prepareCohereTools")
struct CoherePrepareToolsTests {
    @Test("returns nil tools when an empty tools array is provided")
    func emptyToolsArray() {
        let result = prepareCohereTools(tools: [], toolChoice: nil)
        #expect(result.tools == nil)
        #expect(result.toolChoice == nil)
        #expect(result.toolWarnings.isEmpty)
    }

    @Test("processes function tools correctly")
    func functionTool() {
        let functionTool = LanguageModelV3Tool.function(.init(
            name: "testFunction",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([:]),
            ]),
            description: "test description"
        ))

        let result = prepareCohereTools(tools: [functionTool], toolChoice: nil)

        #expect(result.tools == [
            .object([
                "type": .string("function"),
                "function": .object([
                    "name": .string("testFunction"),
                    "description": .string("test description"),
                    "parameters": .object([
                        "type": .string("object"),
                        "properties": .object([:]),
                    ]),
                ]),
            ]),
        ])
        #expect(result.toolChoice == nil)
        #expect(result.toolWarnings.isEmpty)
    }

    @Test("adds warnings for provider-defined tools and returns an empty tools array")
    func providerDefinedTool() {
        let providerTool = LanguageModelV3Tool.provider(.init(
            id: "provider.tool",
            name: "tool",
            args: [:]
        ))

        let result = prepareCohereTools(tools: [providerTool], toolChoice: nil)

        #expect(result.tools == [])
        #expect(result.toolChoice == nil)
        #expect(result.toolWarnings == [
            .unsupported(feature: "provider-defined tool provider.tool", details: nil),
        ])
    }

    @Suite("tool choice handling")
    struct ToolChoiceHandlingTests {
        private var basicTool: LanguageModelV3Tool {
            .function(.init(
                name: "testFunction",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([:]),
                ]),
                description: "test description"
            ))
        }

        @Test("handles auto tool choice")
        func autoToolChoice() {
            let result = prepareCohereTools(tools: [basicTool], toolChoice: .auto)
            #expect(result.toolChoice == nil)
        }

        @Test("handles none tool choice")
        func noneToolChoice() {
            let result = prepareCohereTools(tools: [basicTool], toolChoice: .some(LanguageModelV3ToolChoice.none))
            #expect(result.toolChoice == .some(.none))
            #expect(result.tools?.isEmpty == false)
        }

        @Test("handles required tool choice")
        func requiredToolChoice() {
            let result = prepareCohereTools(tools: [basicTool], toolChoice: .required)
            #expect(result.toolChoice == .required)
            #expect(result.tools?.isEmpty == false)
        }

        @Test("handles tool tool choice by filtering tools")
        func toolToolChoiceFiltersTools() {
            let result = prepareCohereTools(tools: [basicTool], toolChoice: .tool(toolName: "testFunction"))
            #expect(result.toolChoice == .required)
            #expect(result.tools?.count == 1)
        }
    }
}
