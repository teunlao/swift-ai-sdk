import Testing

@testable import AISDKProvider
@testable import AISDKProviderUtils

@Suite("createToolNameMapping")
struct ToolNameMappingTests {
    @Test("creates mappings for provider-defined tools")
    func createsMappingsForProviderDefinedTools() {
        let tools: [LanguageModelV4Tool] = [
            .provider(.init(
                id: "anthropic.computer-use",
                name: "custom-computer-tool",
                args: [:]
            )),
            .provider(.init(
                id: "openai.code-interpreter",
                name: "custom-code-tool",
                args: [:]
            )),
        ]

        let mapping = createToolNameMapping(
            tools: tools,
            providerToolNames: [
                "anthropic.computer-use": "computer_use",
                "openai.code-interpreter": "code_interpreter",
            ]
        )

        #expect(mapping.toProviderToolName("custom-computer-tool") == "computer_use")
        #expect(mapping.toProviderToolName("custom-code-tool") == "code_interpreter")
        #expect(mapping.toCustomToolName("computer_use") == "custom-computer-tool")
        #expect(mapping.toCustomToolName("code_interpreter") == "custom-code-tool")
    }

    @Test("ignores function tools")
    func ignoresFunctionTools() {
        let tools: [LanguageModelV4Tool] = [
            .function(.init(
                name: "my-function-tool",
                inputSchema: .object(["type": .string("object")]),
                description: "A function tool"
            )),
        ]

        let mapping = createToolNameMapping(
            tools: tools,
            providerToolNames: [:]
        )

        #expect(mapping.toProviderToolName("my-function-tool") == "my-function-tool")
        #expect(mapping.toCustomToolName("my-function-tool") == "my-function-tool")
    }

    @Test("returns input name when provider tool id is not mapped")
    func returnsInputNameWhenProviderToolIdIsNotMapped() {
        let tools: [LanguageModelV4Tool] = [
            .provider(.init(
                id: "unknown.tool",
                name: "custom-tool",
                args: [:]
            )),
        ]

        let mapping = createToolNameMapping(
            tools: tools,
            providerToolNames: [:]
        )

        #expect(mapping.toProviderToolName("custom-tool") == "custom-tool")
        #expect(mapping.toCustomToolName("unknown-name") == "unknown-name")
    }

    @Test("returns input name when mapping does not exist")
    func returnsInputNameWhenMappingDoesNotExist() {
        let tools: [LanguageModelV4Tool] = [
            .provider(.init(
                id: "anthropic.computer-use",
                name: "custom-computer-tool",
                args: [:]
            )),
        ]

        let mapping = createToolNameMapping(
            tools: tools,
            providerToolNames: [
                "anthropic.computer-use": "computer_use"
            ]
        )

        #expect(mapping.toProviderToolName("non-existent-tool") == "non-existent-tool")
        #expect(mapping.toCustomToolName("non-existent-provider-tool") == "non-existent-provider-tool")
    }

    @Test("handles empty and nil tools")
    func handlesEmptyAndNilTools() {
        let emptyMapping = createToolNameMapping(
            tools: [],
            providerToolNames: [:]
        )
        let nilMapping = createToolNameMapping(
            providerToolNames: [:]
        )

        #expect(emptyMapping.toProviderToolName("any-tool") == "any-tool")
        #expect(emptyMapping.toCustomToolName("any-tool") == "any-tool")
        #expect(nilMapping.toProviderToolName("any-tool") == "any-tool")
        #expect(nilMapping.toCustomToolName("any-tool") == "any-tool")
    }

    @Test("handles mixed function and provider-defined tools")
    func handlesMixedFunctionAndProviderDefinedTools() {
        let tools: [LanguageModelV4Tool] = [
            .function(.init(
                name: "function-tool",
                inputSchema: .object(["type": .string("object")]),
                description: "A function tool"
            )),
            .provider(.init(
                id: "anthropic.computer-use",
                name: "provider-tool",
                args: [:]
            )),
        ]

        let mapping = createToolNameMapping(
            tools: tools,
            providerToolNames: [
                "anthropic.computer-use": "computer_use"
            ]
        )

        #expect(mapping.toProviderToolName("function-tool") == "function-tool")
        #expect(mapping.toCustomToolName("function-tool") == "function-tool")
        #expect(mapping.toProviderToolName("provider-tool") == "computer_use")
        #expect(mapping.toCustomToolName("computer_use") == "provider-tool")
    }
}
