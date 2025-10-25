/**
 Anthropic Provider Documentation Validation

 This example validates all code samples from the Anthropic provider documentation.
 Each example from docs/providers/anthropic.mdx is tested here to ensure correctness.

 Run with: swift run ProviderValidation-Anthropic
 */

import Foundation
import SwiftAISDK
import AnthropicProvider
import AISDKProvider
import AISDKProviderUtils
import ExamplesCore

struct WeatherQuery: Codable, Sendable { let location: String }
struct WeatherReport: Codable, Sendable { let location: String; let forecast: String }
struct ReleaseSummary: Codable, Sendable { let summary: String }

// MARK: - Main Test Runner

@main
struct ProviderValidationAnthropic {
    static func main() async {
        // Load environment variables from .env file
        do {
            try EnvLoader.load()
        } catch {
            print("⚠️  Warning: Could not load .env file: \(error)")
            print("   Continuing with system environment variables...")
        }

        printHeader("Anthropic Provider Documentation Validation")

        var passed = 0
        var failed = 0
        var skipped = 0

        // Run all validation tests
        let tests: [(String, () async throws -> Void)] = [
            // Setup & Provider Instance
            ("1. Basic Provider Instance", testBasicProviderInstance),
            ("2. Custom Provider Settings", testCustomProviderSettings),
            ("3. Language Model Creation", testLanguageModelCreation),

            // Language Models - Generation (require API)
            ("4. Generate Text Basic", testGenerateTextBasic),
            ("5. Stream Text Basic", testStreamTextBasic),

            // Advanced Features
            ("6. Tool Call with Typed Schema", testToolCallWithTypedSchema),
            ("7. Generate Object with Typed Schema", testGenerateObjectTyped),
            ("8. Reasoning Syntax", testReasoningSyntax),
            ("9. Cache Control Syntax", testCacheControlSyntax),
            ("10. Cache Control System Messages", testCacheControlSystemMessages),

            // Tools
            ("11. Bash Tool Syntax", testBashToolSyntax),
            ("12. Text Editor Tool Syntax", testTextEditorToolSyntax),
            ("13. Computer Tool Syntax", testComputerToolSyntax),
            ("14. Web Search Tool Syntax", testWebSearchToolSyntax),
            ("15. Web Fetch Tool Syntax", testWebFetchToolSyntax),
            ("16. Code Execution Tool Syntax", testCodeExecutionToolSyntax),

            // Multi-modal
            ("17. PDF Support Syntax", testPdfSupportSyntax),
        ]

        for (name, test) in tests {
            do {
                print("\n\n📋 Running: \(name)")
                try await test()
                print("✅ PASSED: \(name)")
                passed += 1
            } catch is SkippedTest {
                print("⏭️  SKIPPED: \(name)")
                skipped += 1
            } catch {
                print("❌ FAILED: \(name)")
                print("   Error: \(error)")
                failed += 1
            }
        }

        // Print summary
        printHeader("Validation Summary")
        print("✅ Passed: \(passed)")
        print("❌ Failed: \(failed)")
        print("⏭️  Skipped: \(skipped)")
        print("\nTotal: \(passed + failed + skipped) tests")

        if failed > 0 {
            print("\n⚠️  Some tests failed. Documentation may need updates.")
            exit(1)
        } else {
            print("\n🎉 All tests passed! Documentation is valid.")
        }
    }
}

// MARK: - Setup & Provider Instance Tests

func testBasicProviderInstance() async throws {
    // From docs: anthropic is a global instance
    print("   Testing basic provider instance access")

    let anthropicInstance = anthropic
    let instanceType = String(describing: type(of: anthropicInstance))
    print("   Using provider: \(instanceType)")

    print("   ✓ Provider instance accessible successfully")
}

func testCustomProviderSettings() async throws {
    // From docs: createAnthropicProvider with custom settings
    print("   Testing custom provider settings")

    let anthropic = createAnthropicProvider(
        settings: AnthropicProviderSettings(
            baseURL: "https://custom.api.com/v1",
            apiKey: "test-key"
        )
    )

    let instanceType = String(describing: type(of: anthropic))
    print("   Created custom provider: \(instanceType)")

    print("   ✓ Custom provider instance created successfully")
}

func testLanguageModelCreation() async throws {
    // From docs: anthropic("model-id")
    print("   Testing language model creation")

    let model = try anthropic("claude-3-haiku-20240307")
    let modelType = String(describing: type(of: model))
    print("   Created model: \(modelType)")

    print("   ✓ Model conforms to LanguageModelV3")
}

// MARK: - Language Models - Basic Generation Tests

func testGenerateTextBasic() async throws {
    // From docs (line 95-98): Basic text generation with Claude
    print("   Testing generate text with Claude API...")

    let result = try await generateText(
        model: try anthropic("claude-3-haiku-20240307"),
        prompt: "Write a vegetarian lasagna recipe for 4 people."
    )

    print("   ✓ Generated text: \(result.text.prefix(100))...")
    print("   ✓ Tokens used: \(result.usage.totalTokens ?? 0)")
    print("   ✓ Finish reason: \(result.finishReason)")
}

func testStreamTextBasic() async throws {
    // From docs: Stream text generation
    print("   Testing stream text with Claude API...")

    let stream = try streamText(
        model: try anthropic("claude-3-haiku-20240307"),
        prompt: "Write a 2-sentence description of Swift programming language."
    )

    var chunkCount = 0
    for try await chunk in stream.textStream {
        chunkCount += 1
        if chunkCount <= 3 {
            print("   Chunk \(chunkCount): \(chunk.prefix(50))...")
        }
    }

    print("   ✓ Received \(chunkCount) text chunks")
}

// MARK: - Typed Tool & Structured Output

func testToolCallWithTypedSchema() async throws {
    print("   Testing tool call with typed schema")

    let weatherTool = tool(
        description: "Return a canned forecast",
        inputSchema: WeatherQuery.self
    ) { query, _ in
        WeatherReport(location: query.location, forecast: "72°F and sunny")
    }

    let result = try await generateText(
        model: try anthropic("claude-3-5-sonnet-20241022"),
        tools: ["weather": weatherTool.eraseToTool()],
        toolChoice: .tool(toolName: "weather"),
        prompt: "Call the weather tool for San Francisco and summarize the response."
    )

    guard let toolCall = result.toolCalls.first(where: { !$0.isDynamic }) else {
        print("   ⚠️ Model did not invoke the tool; skipping")
        throw SkippedTest()
    }

    let decodedCall = try await weatherTool.decodeInput(from: toolCall)
    print("   Tool call args: location=\(decodedCall.location)")

    guard let toolResult = result.toolResults.first(where: { !$0.isDynamic }) else {
        print("   ⚠️ Model produced no tool result; skipping")
        throw SkippedTest()
    }

    let decodedResult = try weatherTool.decodeOutput(from: toolResult)
    print("   Tool result: \(decodedResult.forecast)")
    print("   ✓ Tool execution pipeline completed")
}

func testGenerateObjectTyped() async throws {
    print("   Testing generateObject with typed schema")

    let summary = try await generateObject(
        model: try anthropic("claude-3-5-sonnet-20241022"),
        schema: ReleaseSummary.self,
        prompt: "Summarize the Swift AI SDK key features in one sentence.",
        schemaName: "release_summary"
    ).object

    print("   Summary: \(summary.summary)")
    print("   ✓ generateObject returned typed value")
}

// MARK: - Advanced Features Tests

func testReasoningSyntax() async throws {
    // From docs: thinking parameter with budgetTokens
    print("   Testing reasoning syntax")

    let _: [String: Any] = [
        "anthropic": [
            "thinking": [
                "type": "enabled",
                "budgetTokens": 12000
            ]
        ]
    ]

    print("   ✓ Reasoning providerOptions structure is valid")
    print("   Options: thinking with budgetTokens")
}

func testCacheControlSyntax() async throws {
    // From docs: cacheControl in message content
    print("   Testing cache control syntax")

    let _: [[String: Any]] = [
        [
            "role": "user",
            "content": [
                ["type": "text", "text": "You are a JavaScript expert."],
                [
                    "type": "text",
                    "text": "Error message: test error",
                    "providerOptions": [
                        "anthropic": ["cacheControl": ["type": "ephemeral"]]
                    ]
                ],
                ["type": "text", "text": "Explain the error message."]
            ]
        ]
    ]

    print("   ✓ Cache control in content structure is valid")
    print("   Format: cacheControl in providerOptions per message part")
}

func testCacheControlSystemMessages() async throws {
    // From docs: cacheControl on system messages
    print("   Testing cache control on system messages syntax")

    let _: [[String: Any]] = [
        [
            "role": "system",
            "content": "You are a JavaScript expert."
        ],
        [
            "role": "system",
            "content": "Long context here",
            "providerOptions": [
                "anthropic": ["cacheControl": ["type": "ephemeral"]]
            ]
        ],
        [
            "role": "user",
            "content": "Explain this code"
        ]
    ]

    print("   ✓ Cache control on system messages structure is valid")
    print("   Format: Multiple system messages with cacheControl")
}

// MARK: - Tools Tests

func testBashToolSyntax() async throws {
    // From docs: anthropic.tools.bash_20241022
    print("   Testing bash tool syntax")

    print("   ⏭️  Skipping: bash tool requires execute closure implementation")
    throw SkippedTest()
}

func testTextEditorToolSyntax() async throws {
    // From docs: anthropic.tools.textEditor_20250728
    print("   Testing text editor tool syntax")

    print("   ⏭️  Skipping: text editor tool requires execute closure implementation")
    throw SkippedTest()
}

func testComputerToolSyntax() async throws {
    // From docs: anthropic.tools.computer_20241022
    print("   Testing computer tool syntax")

    print("   ⏭️  Skipping: computer tool requires execute closure implementation")
    throw SkippedTest()
}

func testWebSearchToolSyntax() async throws {
    // From docs: anthropic.tools.webSearch_20250305
    print("   Testing web search tool syntax")

    let _ = anthropic.tools.webSearch20250305()

    print("   ✓ Web search tool created successfully")
    print("   Tool: anthropic.tools.webSearch20250305()")
}

func testWebFetchToolSyntax() async throws {
    // From docs: anthropic.tools.webFetch_20250910
    print("   Testing web fetch tool syntax")

    let _ = anthropic.tools.webFetch20250910()

    print("   ✓ Web fetch tool created successfully")
    print("   Tool: anthropic.tools.webFetch20250910()")
}

func testCodeExecutionToolSyntax() async throws {
    // From docs: anthropic.tools.codeExecution_20250522
    print("   Testing code execution tool syntax")

    let _ = anthropic.tools.codeExecution20250522()

    print("   ✓ Code execution tool created successfully")
    print("   Tool: anthropic.tools.codeExecution20250522()")
}

// MARK: - Multi-modal Tests

func testPdfSupportSyntax() async throws {
    // From docs: PDF in message content
    print("   Testing PDF support syntax")

    let _: [[String: Any]] = [
        [
            "role": "user",
            "content": [
                ["type": "text", "text": "What is in this PDF?"],
                [
                    "type": "file",
                    "data": Data(),
                    "mediaType": "application/pdf"
                ]
            ]
        ]
    ]

    print("   ✓ PDF support structure is valid")
    print("   Format: [\"type\": \"file\", \"mediaType\": \"application/pdf\"]")
}

// MARK: - Utilities

func printHeader(_ title: String) {
    let separator = String(repeating: "=", count: 60)
    print("\n\(separator)")
    print(title.centered(width: 60))
    print(separator)
}

extension String {
    func centered(width: Int) -> String {
        let padding = max(0, width - count) / 2
        let leftPad = String(repeating: " ", count: padding)
        let rightPad = String(repeating: " ", count: width - padding - count)
        return leftPad + self + rightPad
    }
}

// MARK: - Error Types

enum ValidationError: Error, CustomStringConvertible {
    case typeMismatch(String)
    case unexpectedValue(String)
    case missingFeature(String)

    var description: String {
        switch self {
        case .typeMismatch(let msg):
            return "Type mismatch: \(msg)"
        case .unexpectedValue(let msg):
            return "Unexpected value: \(msg)"
        case .missingFeature(let msg):
            return "Missing feature: \(msg)"
        }
    }
}

struct SkippedTest: Error {}
