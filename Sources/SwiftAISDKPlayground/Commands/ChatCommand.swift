import ArgumentParser
import Foundation
import SwiftAISDK
import AISDKProvider
import AISDKProviderUtils

struct ChatCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "chat",
        abstract: "Generate text model response via Swift AI SDK."
    )

    @OptionGroup
    var global: GlobalOptions

    @Option(name: [.customShort("P"), .long], help: "Provider (gateway, openai, anthropic ...). Defaults to configuration.")
    var provider: String?

    @Option(name: .shortAndLong, help: "Model identifier (required).")
    var model: String

    @Option(name: .shortAndLong, help: "Single-line prompt. Or use --input-file / stdin.")
    var prompt: String?

    @Option(name: .long, help: "Path to file with prompt.")
    var inputFile: String?

    @Flag(name: .shortAndLong, help: "Enable streaming output.")
    var stream: Bool = false

    @Flag(name: .long, help: "Output result in JSON format (final result).")
    var jsonOutput: Bool = false

    @Flag(name: .long, help: "Read prompt from standard input.")
    var stdin: Bool = false

    @Flag(name: .long, help: "Enable demo tools (weather, calculator).")
    var withTools: Bool = false

    @MainActor
    func run() async throws {
        try await global.bootstrapContext()

        guard let context = PlaygroundContext.shared else {
            throw ContextError.missingRootContext
        }

        await context.logger.verbose("Initializing chat command")

        let inputText = try await resolvePromptText(logger: context.logger)
        let chosenProvider = provider ?? context.configuration.defaultProvider

        let languageModel = try ProviderFactory.makeLanguageModel(
            provider: chosenProvider,
            modelId: model,
            configuration: context.configuration,
            logger: context.logger
        )

        let tools: ToolSet? = withTools ? createDemoTools() : nil

        if stream {
            if #available(macOS 13.0, *) {
                try await runStreaming(
                    model: languageModel,
                    promptText: inputText,
                    tools: tools,
                    logger: context.logger
                )
            } else if tools != nil {
                await context.logger.verbose("⚠️ Streaming with tools requires macOS 13.0+")
                throw ContextError.toolsRequireMacOS13
            } else {
                // Fallback for old macOS without tools
                let callOptions = try await buildCallOptions(for: languageModel, promptText: inputText)
                let streamResult = try await languageModel.doStream(options: callOptions)

                for try await part in streamResult.stream {
                    switch part {
                    case .textDelta(_, let delta, _):
                        print(delta, terminator: "")
                        fflush(stdout)
                    default:
                        break
                    }
                }
                print()
            }
        } else {
            try await runSynchronous(
                model: languageModel,
                promptText: inputText,
                tools: tools,
                jsonOutput: jsonOutput,
                logger: context.logger
            )
        }
    }

    private func resolvePromptText(logger: PlaygroundLogger) async throws -> String {
        if let prompt {
            return prompt
        }

        if let inputFile {
            let url = URL(fileURLWithPath: inputFile)
            return try String(contentsOf: url, encoding: .utf8)
        }

        if stdin {
            await logger.verbose("Reading prompt from stdin...")
            var buffer = ""
            while let line = readLine() {
                buffer.append(line)
                buffer.append("\n")
            }
            return buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        throw ContextError.missingPrompt
    }

    private func runSynchronous(
        model: any LanguageModelV3,
        promptText: String,
        tools: ToolSet?,
        jsonOutput: Bool,
        logger: PlaygroundLogger
    ) async throws {
        if let tools = tools {
            if #available(macOS 13.0, *) {
                try await runWithTools(model: model, promptText: promptText, tools: tools, jsonOutput: jsonOutput, logger: logger)
            } else {
                await logger.verbose("⚠️ Tools require macOS 13.0+")
                throw ContextError.toolsRequireMacOS13
            }
            return
        }

        // Non-tools synchronous path

        let callOptions = try await buildCallOptions(for: model, promptText: promptText)
        let response = try await model.doGenerate(options: callOptions)

        let text = extractText(from: response.content)

        if jsonOutput {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let payload = PlaygroundJSONResult(
                text: text,
                usage: asLanguageModelUsage(response.usage),
                finishReason: response.finishReason,
                warnings: response.warnings
            )
            let data = try encoder.encode(payload)
            print(String(decoding: data, as: UTF8.self))
        } else {
            print(text)
            await logger.verbose("usage: \(String(describing: response.usage))")
        }
    }

    @available(macOS 13.0, *)
    private func runStreaming(
        model: any LanguageModelV3,
        promptText: String,
        tools: ToolSet?,
        logger: PlaygroundLogger
    ) async throws {
        if let tools = tools {
            try await runStreamingWithTools(model: model, promptText: promptText, tools: tools, logger: logger)
            return
        }

        let callOptions = try await buildCallOptions(for: model, promptText: promptText)
        let streamResult = try await model.doStream(options: callOptions)

        var aggregatedText = ""
        var finishReason: FinishReason?

        for try await part in streamResult.stream {
            switch part {
            case .textDelta(_, let delta, _):
                aggregatedText.append(delta)
                print(delta, terminator: "")
                fflush(stdout)
            case .textStart, .textEnd:
                break
            case .finish(let reason, _, _):
                finishReason = reason
            default:
                await logger.verbose("Skipped stream chunk: \(part)")
            }
        }

        print()

        if let finishReason {
            await logger.verbose("finishReason: \(finishReason.rawValue)")
        }
    }

    private func buildCallOptions(
        for model: any LanguageModelV3,
        promptText: String
    ) async throws -> LanguageModelV3CallOptions {
        let prompt = Prompt.text(promptText)
        let standardized = try standardizePrompt(prompt)
        let supported = try await model.supportedUrls
        let languagePrompt = try await convertToLanguageModelPrompt(
            prompt: standardized,
            supportedUrls: supported
        )
        return LanguageModelV3CallOptions(prompt: languagePrompt)
    }

    private func extractText(from content: [LanguageModelV3Content]) -> String {
        var output = ""
        for part in content {
            switch part {
            case .text(let textPart):
                output.append(textPart.text)
            case .toolCall, .toolResult, .toolApprovalRequest, .reasoning, .file, .source:
                continue
            }
        }
        return output
    }

    @available(macOS 13.0, *)
    private func runWithTools(
        model: any LanguageModelV3,
        promptText: String,
        tools: ToolSet,
        jsonOutput: Bool,
        logger: PlaygroundLogger
    ) async throws {
        await logger.verbose("Using \(tools.count) tool(s)")

        let result: DefaultGenerateTextResult<JSONValue> = try await generateText(
            model: .v3(model),
            tools: tools,
            prompt: promptText
        )

        if jsonOutput {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(PlaygroundToolJSONResult(
                text: extractContentText(from: result.content),
                usage: result.usage,
                finishReason: result.finishReason,
                steps: result.steps.count,
                toolCalls: countToolCalls(in: result.content),
                toolResults: countToolResults(in: result.content)
            ))
            print(String(decoding: data, as: UTF8.self))
        } else {
            // Pretty console output
            print("📊 Results:\n")
            print("Steps: \(result.steps.count)")
            print("Finish reason: \(result.finishReason.rawValue)")
            print("Usage: \(result.usage.totalTokens ?? 0) tokens\n")

            for (index, content) in result.content.enumerated() {
                switch content {
                case .text(let text, _):
                    print("[\(index)] 💬 \(text)")
                case .toolCall(let call, _):
                    print("[\(index)] 🔧 Tool: \(call.toolName)")
                    print("       Input: \(call.input)")
                case .toolResult(let res, _):
                    print("[\(index)] ✅ Result: \(res.toolName)")
                    print("       Output: \(res.output)")
                default:
                    break
                }
            }
        }

        await logger.verbose("usage: \(String(describing: result.usage))")
    }

    private func countToolCalls(in content: [ContentPart]) -> Int {
        content.filter { if case .toolCall = $0 { return true }; return false }.count
    }

    private func countToolResults(in content: [ContentPart]) -> Int {
        content.filter { if case .toolResult = $0 { return true }; return false }.count
    }

    private func extractContentText(from content: [ContentPart]) -> String {
        var output = ""
        for part in content {
            switch part {
            case .text(let text, _):
                output.append(text)
            default:
                continue
            }
        }
        return output
    }

    @available(macOS 13.0, *)
    private func runStreamingWithTools(
        model: any LanguageModelV3,
        promptText: String,
        tools: ToolSet,
        logger: PlaygroundLogger
    ) async throws {
        await logger.verbose("Streaming with \(tools.count) tool(s)")

        let result: DefaultStreamTextResult<JSONValue, JSONValue> = try streamText(
            model: .v3(model),
            prompt: promptText,
            tools: tools
        )

        var stepNumber = 0
        var totalUsage = LanguageModelUsage(inputTokens: 0, outputTokens: 0, totalTokens: 0)

        for try await part in result.fullStream {
            switch part {
            case .textDelta(_, let delta, _):
                print(delta, terminator: "")
                fflush(stdout)

            case .toolCall(let toolCall):
                switch toolCall {
                case .static(let call):
                    print("\n🔧 [Tool Call] \(call.toolName)")
                    await logger.verbose("   Args: \(call.input)")
                case .dynamic(let call):
                    print("\n🔧 [Dynamic Tool] \(call.toolName)")
                    await logger.verbose("   Args: \(call.input)")
                }

            case .toolResult(let toolResult):
                switch toolResult {
                case .static(let result):
                    print("✅ [Tool Result] \(result.toolName)")
                    await logger.verbose("   Output: \(result.output)")
                case .dynamic(let result):
                    print("✅ [Dynamic Result] \(result.toolName)")
                    await logger.verbose("   Output: \(result.output)")
                }

            case .finishStep(_, let usage, let finishReason, let rawFinishReason, _):
                stepNumber += 1
                print("\n")
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                print("📍 Step \(stepNumber) completed")
                print("   Reason: \(finishReason.rawValue)")
                if let rawFinishReason {
                    print("   Raw reason: \(rawFinishReason)")
                }
                print("   Usage: \(usage.totalTokens ?? 0) tokens")
                totalUsage = addLanguageModelUsage(totalUsage, usage)
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

            case .finish(let finishReason, let rawFinishReason, let usage):
                print("\n")
                print("🏁 Completed")
                print("   Final reason: \(finishReason.rawValue)")
                if let rawFinishReason {
                    print("   Raw reason: \(rawFinishReason)")
                }
                print("   Total usage: \(usage.totalTokens ?? totalUsage.totalTokens ?? 0) tokens")
                print("   Steps: \(stepNumber)")

            case .error(let error):
                print("\n❌ Error: \(error)")

            default:
                await logger.verbose("Unhandled stream part: \(part)")
            }
        }

        print("\n")
    }
}

private func createDemoTools() -> ToolSet {
    [
        "getWeather": createWeatherTool(),
        "calculate": createCalculatorTool()
    ]
}

private func createWeatherTool() -> Tool {
    tool(
        description: "Get the weather in a location",
        inputSchema: FlexibleSchema<JSONValue>(jsonSchema(JSONValue.object([
                "$schema": JSONValue.string("http://json-schema.org/draft-07/schema#"),
                "type": JSONValue.string("object"),
                "properties": JSONValue.object([
                    "location": JSONValue.object([
                        "type": JSONValue.string("string"),
                        "description": JSONValue.string("The location to get the weather for")
                    ])
                ]),
                "required": JSONValue.array([JSONValue.string("location")]),
                "additionalProperties": JSONValue.bool(false)
            ]))),
        execute: { input, _ in
            guard case .object(let obj) = input,
                  case .string(let location) = obj["location"] else {
                return .value(.object(["error": .string("Invalid input")]))
            }

            let temperature = 72 + Int.random(in: -10...10)

            return .value(.object([
                "location": .string(location),
                "temperature": .number(Double(temperature)),
                "unit": .string("fahrenheit")
            ]))
        }
    )
}

private func createCalculatorTool() -> Tool {
    tool(
        description: "Perform basic math operations (add, subtract, multiply, divide)",
        inputSchema: FlexibleSchema<JSONValue>(jsonSchema(JSONValue.object([
                "$schema": JSONValue.string("http://json-schema.org/draft-07/schema#"),
                "type": JSONValue.string("object"),
                "properties": JSONValue.object([
                    "operation": JSONValue.object([
                        "type": JSONValue.string("string"),
                        "enum": JSONValue.array([JSONValue.string("add"), JSONValue.string("subtract"), JSONValue.string("multiply"), JSONValue.string("divide")]),
                        "description": JSONValue.string("Math operation to perform")
                    ]),
                    "a": JSONValue.object([
                        "type": JSONValue.string("number"),
                        "description": JSONValue.string("First number")
                    ]),
                    "b": JSONValue.object([
                        "type": JSONValue.string("number"),
                        "description": JSONValue.string("Second number")
                    ])
                ]),
                "required": JSONValue.array([JSONValue.string("operation"), JSONValue.string("a"), JSONValue.string("b")]),
                "additionalProperties": JSONValue.bool(false)
            ]))),
        execute: { input, _ in
            guard case .object(let obj) = input,
                  case .string(let op) = obj["operation"],
                  case .number(let a) = obj["a"],
                  case .number(let b) = obj["b"] else {
                return .value(.object(["error": .string("Invalid input")]))
            }

            let result: Double
            switch op {
            case "add": result = a + b
            case "subtract": result = a - b
            case "multiply": result = a * b
            case "divide": result = b != 0 ? a / b : Double.nan
            default: result = 0
            }

            return .value(.object([
                "result": .number(result),
                "operation": .string(op)
            ]))
        }
    )
}

private struct PlaygroundJSONResult: Codable {
    let text: String
    let usage: LanguageModelUsage
    let finishReason: FinishReason
    let warnings: [CallWarning]?
}

private struct PlaygroundToolJSONResult: Codable {
    let text: String
    let usage: LanguageModelUsage
    let finishReason: FinishReason
    let steps: Int
    let toolCalls: Int
    let toolResults: Int
}

enum ContextError: LocalizedError {
    case missingRootContext
    case unsupportedProvider(String)
    case missingPrompt
    case missingAPIKey(provider: String)
    case toolsRequireMacOS13

    var errorDescription: String? {
        switch self {
        case .missingRootContext:
            return "Internal error: CLI context not initialized. Run command via `swift run playground ...`."
        case .unsupportedProvider(let provider):
            return "Provider \(provider) is not yet supported."
        case .missingPrompt:
            return "Specify prompt via --prompt, --input-file or --stdin."
        case .missingAPIKey(let provider):
            return "API key for provider \(provider) not found. Add it to environment variables or .env file."
        case .toolsRequireMacOS13:
            return "Using tools requires macOS 13.0 or newer."
        }
    }
}
