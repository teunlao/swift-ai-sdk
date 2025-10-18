import AISDKProvider
import AISDKProviderUtils
import SwiftAISDK
import Testing

@Suite("Agent")
struct AgentTests {
    @Test("generate applies agent settings")
    func generateAppliesSettings() async throws {
        let mockModel = MockLanguageModel()
        let emptySchema = jsonSchema(
            .object([
                "type": .string("object"),
                "properties": .object([:]),
                "additionalProperties": .bool(false)
            ])
        )
        let echoTool = Tool(
            description: "Echo",
            inputSchema: FlexibleSchema(emptySchema)
        )
        let settings = AgentSettings<String, Never>(
            name: "helper",
            system: "You are helpful",
            model: .v3(mockModel),
            tools: ["echo": echoTool],
            toolChoice: .required,
            stopWhen: nil,
            experimentalTelemetry: nil,
            activeTools: nil,
            experimentalOutput: nil,
            experimentalPrepareStep: nil,
            prepareStep: nil,
            experimentalRepairToolCall: nil,
            onStepFinish: nil,
            onFinish: nil,
            providerOptions: ["openai": ["mode": .string("fast")]],
            experimentalContext: nil,
            callSettings: CallSettings(maxOutputTokens: 42, temperature: 0.1)
        )

        let agent = Agent<String, Never>(settings: settings)
        let result = try await agent.generate(prompt: .text("Hello"))
        #expect(result.text.isEmpty)

        guard let options = mockModel.lastGenerateOptions else {
            Issue.record("Expected language model to be invoked")
            return
        }

        guard case let .system(systemContent, _) = options.prompt.first else {
            Issue.record("Expected first message to be system")
            return
        }
        #expect(systemContent == "You are helpful")

        guard case let .user(userContent, _) = options.prompt.last else {
            Issue.record("Expected user message")
            return
        }
        guard case let .text(textPart) = userContent.first else {
            Issue.record("Expected text part in user message")
            return
        }
        #expect(textPart.text == "Hello")

        // Call settings are forwarded.
        #expect(options.maxOutputTokens == 42)
        #expect(options.temperature == 0.1)
        #expect(options.tools?.count == 1)
        #expect(options.toolChoice == .required)
        #expect(options.providerOptions?["openai"]?["mode"] == .string("fast"))
    }

    @Test("stream standardizes prompt and records system message")
    func streamStandardizesPrompt() async throws {
        let mockModel = MockLanguageModel()
        let settings = AgentSettings<Never, Never>(
            system: "Context",
            model: .v3(mockModel)
        )

        let agent = Agent<Never, Never>(settings: settings)
        let result = try agent.stream(prompt: .messages([
            .user(UserModelMessage(content: .text("Ping")))
        ]))
        _ = try await result.collectText()

        guard let options = mockModel.lastStreamOptions else {
            Issue.record("Expected stream invocation")
            return
        }

        guard case let .system(systemContent, _) = options.prompt.first else {
            Issue.record("Expected system message to lead prompt")
            return
        }
        #expect(systemContent == "Context")
    }

    @Test("respond converts UI messages before streaming")
    func respondConvertsMessages() async throws {
        let mockModel = MockLanguageModel()
        let settings = AgentSettings<Never, Never>(
            model: .v3(mockModel),
            tools: [:]
        )
        let agent = Agent<Never, Never>(settings: settings)

        let uiMessage = UIMessage(
            id: "user-1",
            role: .user,
            parts: [.text(TextUIPart(text: "Hi there"))]
        )

        let response = try agent.respond(messages: [uiMessage])
        var iterator = response.stream.makeAsyncIterator()
        while try await iterator.next() != nil {}

        guard let options = mockModel.lastStreamOptions else {
            Issue.record("Expected stream invocation")
            return
        }

        guard case let .user(userContent, _) = options.prompt.last else {
            Issue.record("Expected user message passed to model")
            return
        }
        guard case let .text(textPart) = userContent.first else {
            Issue.record("Expected text part")
            return
        }
        #expect(textPart.text == "Hi there")
    }
}

// MARK: - Test doubles

private final class MockLanguageModel: LanguageModelV3, @unchecked Sendable {
    var lastGenerateOptions: LanguageModelV3CallOptions?
    var lastStreamOptions: LanguageModelV3CallOptions?

    func doGenerate(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3GenerateResult {
        lastGenerateOptions = options
        return LanguageModelV3GenerateResult(
            content: [],
            finishReason: .stop,
            usage: LanguageModelV3Usage()
        )
    }

    func doStream(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3StreamResult {
        lastStreamOptions = options
        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { continuation in
            continuation.finish()
        }
        return LanguageModelV3StreamResult(stream: stream)
    }

    var provider: String { "mock" }
    var modelId: String { "mock-model" }
}
