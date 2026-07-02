import Foundation
import Testing
@testable import SwiftAISDK
import AISDKProvider
import AISDKProviderUtils

@Suite("GenerateText V4 Tests")
struct GenerateTextV4Tests {
    private actor CapturedV4Options {
        private var value: LanguageModelV4CallOptions?

        func record(_ options: LanguageModelV4CallOptions) {
            value = options
        }

        func recorded() -> LanguageModelV4CallOptions? {
            value
        }
    }

    @Test("generateText calls V4 model with V4 prompt tools toolChoice and reasoning")
    func generateTextUsesLanguageModelV4Contract() async throws {
        let captured = CapturedV4Options()
        let model = MockLanguageModelV4(
            provider: "mock-v4-provider",
            modelId: "mock-v4-model",
            doGenerate: .function { options in
                await captured.record(options)

                return LanguageModelV4GenerateResult(
                    content: [
                        .text(LanguageModelV4Text(text: "Hello from V4")),
                        .custom(LanguageModelV4CustomContent(kind: "v4-custom")),
                        .reasoningFile(LanguageModelV4ReasoningFile(
                            mediaType: "text/plain",
                            data: .base64("cmVhc29uaW5nLWZpbGU=")
                        )),
                        .source(.url(
                            id: "src-1",
                            url: "https://example.com/v4",
                            title: "V4 Source",
                            providerMetadata: nil
                        )),
                        .toolCall(LanguageModelV4ToolCall(
                            toolCallId: "call-1",
                            toolName: "echo",
                            input: #"{"value":"swift"}"#
                        ))
                    ],
                    finishReason: LanguageModelV4FinishReason(unified: .toolCalls, raw: "tool_calls"),
                    usage: LanguageModelV4Usage(
                        inputTokens: .init(total: 5),
                        outputTokens: .init(total: 7)
                    ),
                    warnings: [
                        .deprecated(setting: "temperature", message: "Use provider defaults.")
                    ]
                )
            }
        )

        let tools: ToolSet = [
            "echo": tool(
                inputSchema: FlexibleSchema(jsonSchema(.object([
                    "type": .string("object"),
                    "properties": .object([
                        "value": .object(["type": .string("string")])
                    ]),
                    "required": .array([.string("value")]),
                    "additionalProperties": .bool(false)
                ]))),
                execute: { input, _ in
                    .value(.object(["echo": input]))
                }
            )
        ]

        let result: DefaultGenerateTextResult<JSONValue> = try await generateText(
            model: .v4(model),
            tools: tools,
            toolChoice: .required,
            system: "You are a V4 contract test.",
            prompt: "Say hello.",
            providerOptions: ["mock": ["mode": .string("v4")]],
            settings: CallSettings(
                temperature: 0.2,
                reasoning: .high,
                headers: ["x-test": "v4"]
            )
        )

        let options = try #require(await captured.recorded())
        #expect(options.reasoning == .high)
        #expect(options.temperature == 0.2)
        #expect(options.headers?["x-test"] == "v4")
        #expect(options.providerOptions?["mock"]?["mode"] == .string("v4"))
        #expect(options.toolChoice == .required)

        #expect(options.prompt.count == 2)
        if case .system(let content, _) = options.prompt[0] {
            #expect(content == "You are a V4 contract test.")
        } else {
            Issue.record("Expected V4 system prompt message")
        }
        if case .user(let content, _) = options.prompt[1],
           case .text(let textPart) = content.first {
            #expect(textPart.text == "Say hello.")
        } else {
            Issue.record("Expected V4 user text prompt message")
        }

        let functionTool = try #require(options.tools?.first)
        if case .function(let tool) = functionTool {
            #expect(tool.name == "echo")
        } else {
            Issue.record("Expected V4 function tool")
        }

        #expect(result.text == "Hello from V4")
        #expect(result.finishReason == .toolCalls)
        #expect(result.rawFinishReason == "tool_calls")
        #expect(result.usage.inputTokens == 5)
        #expect(result.usage.outputTokens == 7)
        #expect(result.sources.count == 1)
        #expect(result.toolCalls.count == 1)
        #expect(result.toolResults.count == 1)

        #expect(result.content.contains { part in
            if case .custom(let kind, _) = part {
                return kind == "v4-custom"
            }
            return false
        })
        #expect(result.content.contains { part in
            if case .reasoningFile(let file, _) = part {
                return file.mediaType == "text/plain" && file.base64 == "cmVhc29uaW5nLWZpbGU="
            }
            return false
        })

        let warning = try #require(result.warnings?.first)
        if case .deprecated(let setting, let message) = warning {
            #expect(setting == "temperature")
            #expect(message == "Use provider defaults.")
        } else {
            Issue.record("Expected V4 deprecated warning")
        }
    }
}
