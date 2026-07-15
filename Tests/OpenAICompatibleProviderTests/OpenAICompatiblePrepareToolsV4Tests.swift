import Testing
@testable import AISDKProvider
@testable import OpenAICompatibleProvider

@Suite("OpenAI-compatible V4 tool preparation")
struct OpenAICompatiblePrepareToolsV4Tests {
    private let schema: JSONValue = .object([
        "type": .string("object"),
        "properties": .object([:])
    ])

    @Test("omits nil and empty tool collections")
    func omitsNilAndEmptyTools() {
        let missing = OpenAICompatibleToolPreparer.prepare(
            tools: Optional<[LanguageModelV4Tool]>.none,
            toolChoice: nil
        )
        #expect(missing.tools == nil)
        #expect(missing.toolChoice == nil)
        #expect(missing.warnings.isEmpty)

        let emptyTools: [LanguageModelV4Tool] = []
        let empty = OpenAICompatibleToolPreparer.prepare(
            tools: emptyTools,
            toolChoice: Optional<LanguageModelV4ToolChoice>.none
        )
        #expect(empty.tools == nil)
        #expect(empty.toolChoice == nil)
        #expect(empty.warnings.isEmpty)
    }

    @Test("serializes function tools and every strict state")
    func serializesFunctionToolsAndStrictStates() {
        let tools: [LanguageModelV4Tool] = [
            .function(.init(
                name: "strictTool",
                inputSchema: schema,
                description: "A strict tool",
                strict: true
            )),
            .function(.init(
                name: "nonStrictTool",
                inputSchema: schema,
                description: "A non-strict tool",
                strict: false
            )),
            .function(.init(
                name: "defaultTool",
                inputSchema: schema,
                description: "A default tool"
            ))
        ]

        let result = OpenAICompatibleToolPreparer.prepare(tools: tools, toolChoice: nil)

        #expect(result.warnings.isEmpty)
        #expect(result.toolChoice == nil)
        #expect(result.tools == .array([
            .object([
                "type": .string("function"),
                "function": .object([
                    "name": .string("strictTool"),
                    "description": .string("A strict tool"),
                    "parameters": schema,
                    "strict": .bool(true)
                ])
            ]),
            .object([
                "type": .string("function"),
                "function": .object([
                    "name": .string("nonStrictTool"),
                    "description": .string("A non-strict tool"),
                    "parameters": schema,
                    "strict": .bool(false)
                ])
            ]),
            .object([
                "type": .string("function"),
                "function": .object([
                    "name": .string("defaultTool"),
                    "description": .string("A default tool"),
                    "parameters": schema
                ])
            ])
        ]))
    }

    @Test("warns for provider tools while preserving the upstream empty array")
    func warnsForProviderTools() {
        let providerTools: [LanguageModelV4Tool] = [
            .provider(LanguageModelV4ProviderTool(
                    id: "some.unsupported_tool",
                    name: "unsupported_tool",
                    args: [:]
                ))
        ]
        let result = OpenAICompatibleToolPreparer.prepare(
            tools: providerTools,
            toolChoice: nil
        )

        #expect(result.tools == JSONValue.array([]))
        #expect(result.toolChoice == nil)
        #expect(result.warnings == [
            SharedV4Warning.unsupported(
                feature: "provider-defined tool some.unsupported_tool",
                details: nil
            )
        ])
    }

    @Test("serializes every tool choice")
    func serializesEveryToolChoice() {
        let tool: [LanguageModelV4Tool] = [
            .function(.init(name: "testFunction", inputSchema: schema))
        ]
        let cases: [(choice: LanguageModelV4ToolChoice, expected: JSONValue)] = [
            (.auto, .string("auto")),
            (.required, .string("required")),
            (.none, .string("none")),
            (
                .tool(toolName: "testFunction"),
                .object([
                    "type": .string("function"),
                    "function": .object(["name": .string("testFunction")])
                ])
            )
        ]

        for testCase in cases {
            let result = OpenAICompatibleToolPreparer.prepare(
                tools: tool,
                toolChoice: testCase.choice
            )
            #expect(result.toolChoice == testCase.expected)
            #expect(result.warnings.isEmpty)
        }
    }
}
