/**
 Anthropic Provider Documentation Validation

 This executable keeps the public Swift examples in the Anthropic provider
 documentation type-checked against the current Provider V4 surface.

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

@main
struct ProviderValidationAnthropic {
    static func main() async {
        try? EnvLoader.load()

        printHeader("Anthropic Provider V4 Documentation Validation")

        let tests: [(String, () async throws -> Void)] = [
            ("Native V4 provider", testNativeV4Provider),
            ("Custom V4 provider", testCustomV4Provider),
            ("Frontier model IDs", testFrontierModelIds),
            ("Normalized xhigh reasoning", testNormalizedXhighReasoning),
            ("Anthropic max effort", testAnthropicMaxEffort),
            ("Adaptive thinking options", testAdaptiveThinkingOptions),
            ("Typed cache-control messages", testCacheControlMessages),
            ("Provider-defined tools", testProviderDefinedTools),
            ("Provider file reference", testProviderFileReference),
            ("V4 upload helpers", testUploadHelperSignatures),
            ("Typed PDF prompt", testPDFPrompt),
            ("Typed tool generation", testTypedToolGeneration),
            ("Live generateText", testLiveGenerateText),
            ("Live streamText", testLiveStreamText),
        ]

        var passed = 0
        var failed = 0
        var skipped = 0

        for (name, test) in tests {
            do {
                print("\nRunning: \(name)")
                try await test()
                print("PASSED: \(name)")
                passed += 1
            } catch is SkippedTest {
                print("SKIPPED: \(name)")
                skipped += 1
            } catch {
                print("FAILED: \(name): \(error)")
                failed += 1
            }
        }

        printHeader("Validation Summary")
        print("Passed: \(passed)")
        print("Failed: \(failed)")
        print("Skipped: \(skipped)")

        if failed > 0 {
            exit(1)
        }
    }
}

// MARK: - Provider V4

func testNativeV4Provider() async throws {
    guard anthropic.specificationVersion == "v4" else {
        throw ValidationError.unexpectedValue("default anthropic provider is not V4")
    }

    let model = try anthropic("claude-sonnet-5")
    guard model.specificationVersion == "v4" else {
        throw ValidationError.unexpectedValue("default Anthropic model is not V4")
    }
}

func testCustomV4Provider() async throws {
    let provider = createAnthropic(
        settings: AnthropicProviderSettings(
            baseURL: "https://proxy.example.com/v1",
            apiKey: "test-key",
            headers: ["x-application": "documentation-validation"]
        )
    )

    let model = try provider.languageModel(modelId: "claude-opus-4-8")
    guard model.specificationVersion == "v4" else {
        throw ValidationError.unexpectedValue("custom Anthropic model is not V4")
    }
}

func testFrontierModelIds() async throws {
    for modelId in [
        "claude-sonnet-5",
        "claude-fable-5",
        "claude-opus-4-8",
        "claude-opus-4-7",
        "claude-opus-4-6",
        "claude-sonnet-4-6",
    ] {
        let model = try anthropic(modelId)
        guard model.specificationVersion == "v4" else {
            throw ValidationError.unexpectedValue("\(modelId) is not a V4 model")
        }
    }

    _ = anthropic.chat("claude-sonnet-5")
    _ = anthropic.messages("claude-sonnet-5")
}

// MARK: - Reasoning and provider options

func testNormalizedXhighReasoning() async throws {
    let settings = CallSettings(reasoning: .xhigh)
    guard settings.reasoning == .xhigh else {
        throw ValidationError.unexpectedValue("xhigh reasoning was not preserved")
    }
}

func testAnthropicMaxEffort() async throws {
    let options: ProviderOptions = [
        "anthropic": ["effort": "max"]
    ]

    guard options["anthropic"]?["effort"] == .string("max") else {
        throw ValidationError.unexpectedValue("Anthropic max effort was not preserved")
    }
}

func testAdaptiveThinkingOptions() async throws {
    let options: ProviderOptions = [
        "anthropic": [
            "thinking": [
                "type": "adaptive",
                "display": "summarized",
            ],
            "effort": "max",
        ]
    ]

    guard case .object(let thinking)? = options["anthropic"]?["thinking"],
          thinking["type"] == .string("adaptive"),
          options["anthropic"]?["effort"] == .string("max") else {
        throw ValidationError.unexpectedValue("adaptive thinking options are malformed")
    }
}

func testCacheControlMessages() async throws {
    let messages: [ModelMessage] = [
        .system(SystemModelMessage(
            content: "You are a Swift concurrency expert.",
            providerOptions: [
                "anthropic": [
                    "cacheControl": ["type": "ephemeral", "ttl": "1h"]
                ]
            ]
        )),
        .user(UserModelMessage(content: .parts([
            .text(TextPart(text: "Review this failure:")),
            .text(TextPart(
                text: "Task cancellation did not reach the stream owner.",
                providerOptions: [
                    "anthropic": ["cacheControl": ["type": "ephemeral"]]
                ]
            )),
        ]))),
    ]

    guard messages.count == 2 else {
        throw ValidationError.unexpectedValue("typed cache-control prompt was not built")
    }
}

// MARK: - Provider-defined tools

func testProviderDefinedTools() async throws {
    let tools: [String: Tool] = [
        "bash": anthropic.tools.bash20250124(),
        "str_replace_based_edit_tool": anthropic.tools.textEditor20250728(
            AnthropicTextEditor20250728Args(maxCharacters: 10_000)
        ),
        "computer": anthropic.tools.computer20251124(
            AnthropicComputerOptions(
                displayWidthPx: 1920,
                displayHeightPx: 1080,
                enableZoom: true
            )
        ),
        "web_search": anthropic.tools.webSearch20260209(
            AnthropicWebSearchOptions(maxUses: 5)
        ),
        "web_fetch": anthropic.tools.webFetch20260209(
            AnthropicWebFetchOptions(
                maxUses: 2,
                citationsEnabled: true,
                maxContentTokens: 20_000
            )
        ),
        "code_execution": anthropic.tools.codeExecution20260120(),
        "memory": anthropic.tools.memory20250818(),
        "advisor": anthropic.tools.advisor20260301(
            AnthropicAdvisor20260301Options(
                model: "claude-opus-4-8",
                maxUses: 3
            )
        ),
        "tool_search": anthropic.tools.toolSearchBm2520251119(),
    ]

    guard tools.count == 9 else {
        throw ValidationError.unexpectedValue("provider-defined tool set is incomplete")
    }
}

// MARK: - Files and skills

func testProviderFileReference() async throws {
    let reference: ProviderReference = ["anthropic": "file_123"]
    let message = ModelMessage.user(UserModelMessage(content: .parts([
        .text(TextPart(text: "Analyze this CSV file.")),
        .file(FilePart(
            data: .reference(reference),
            mediaType: "text/csv",
            filename: "data.csv",
            providerOptions: [
                "anthropic": ["containerUpload": true]
            ]
        )),
    ])))

    guard case .user(let user) = message,
          case .parts(let parts) = user.content,
          parts.count == 2 else {
        throw ValidationError.unexpectedValue("provider-reference prompt was not built")
    }
}

func uploadCSVForCodeExecution(_ data: Data) async throws -> DefaultUploadFileResult {
    try await uploadFile(
        api: anthropic,
        data: DataContentOrURL.data(data),
        mediaType: "text/csv",
        filename: "data.csv"
    )
}

func uploadDocumentationSkill() async throws -> DefaultUploadSkillResult {
    try await uploadSkill(
        api: anthropic,
        files: [
            SkillsV4File(
                path: "SKILL.md",
                content: .text("# Data review\nAnalyze the supplied dataset.")
            )
        ],
        displayTitle: "Data review"
    )
}

func testUploadHelperSignatures() async throws {
    let fileUploader: (Data) async throws -> DefaultUploadFileResult =
        uploadCSVForCodeExecution
    let skillUploader: () async throws -> DefaultUploadSkillResult =
        uploadDocumentationSkill

    _ = fileUploader
    _ = skillUploader
}

func testPDFPrompt() async throws {
    let message = ModelMessage.user(UserModelMessage(content: .parts([
        .text(TextPart(text: "Summarize this PDF.")),
        .file(FilePart(
            data: .data(Data([0x25, 0x50, 0x44, 0x46])),
            mediaType: "application/pdf",
            filename: "guide.pdf"
        )),
    ])))

    guard case .user = message else {
        throw ValidationError.unexpectedValue("typed PDF prompt was not built")
    }
}

// MARK: - Live API examples

func testTypedToolGeneration() async throws {
    try requireAnthropicAPIKey()

    let weatherTool = tool(
        description: "Return a canned forecast",
        inputSchema: WeatherQuery.self
    ) { query, _ in
        WeatherReport(location: query.location, forecast: "22 C and sunny")
    }

    let result = try await generateText(
        model: try anthropic("claude-sonnet-5"),
        tools: ["weather": weatherTool.eraseToTool()],
        toolChoice: .tool(toolName: "weather"),
        prompt: "Call the weather tool for San Francisco."
    )

    guard let call = result.toolCalls.first(where: { !$0.isDynamic }) else {
        throw ValidationError.missingFeature("model did not call the weather tool")
    }

    _ = try await weatherTool.decodeInput(from: call)
}

func testLiveGenerateText() async throws {
    try requireAnthropicAPIKey()

    let result = try await generateText(
        model: try anthropic("claude-sonnet-5"),
        prompt: "Describe Swift structured concurrency in one sentence.",
        settings: CallSettings(reasoning: .high)
    )

    guard !result.text.isEmpty else {
        throw ValidationError.unexpectedValue("generateText returned no text")
    }
}

func testLiveStreamText() async throws {
    try requireAnthropicAPIKey()

    let result = try streamText(
        model: try anthropic("claude-sonnet-5"),
        prompt: "Give one benefit of actor isolation."
    )

    var receivedText = false
    for try await text in result.textStream {
        receivedText = receivedText || !text.isEmpty
    }

    guard receivedText else {
        throw ValidationError.unexpectedValue("streamText returned no text")
    }
}

// MARK: - Utilities

func requireAnthropicAPIKey() throws {
    guard let key = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"],
          !key.isEmpty else {
        throw SkippedTest()
    }
}

func printHeader(_ title: String) {
    let separator = String(repeating: "=", count: 64)
    print("\n\(separator)")
    print(title)
    print(separator)
}

enum ValidationError: Error, CustomStringConvertible {
    case unexpectedValue(String)
    case missingFeature(String)

    var description: String {
        switch self {
        case .unexpectedValue(let message):
            return "Unexpected value: \(message)"
        case .missingFeature(let message):
            return "Missing feature: \(message)"
        }
    }
}

struct SkippedTest: Error {}
