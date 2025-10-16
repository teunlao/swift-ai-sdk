import ArgumentParser
import Foundation
import SwiftAISDK
import AISDKProvider

struct ChatCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "chat",
        abstract: "Сгенерировать ответ модели текста через Swift AI SDK."
    )

    @OptionGroup
    var global: GlobalOptions

    @Option(name: [.customShort("P"), .long], help: "Провайдер (gateway, openai, anthropic ...). По умолчанию берётся из конфигурации.")
    var provider: String?

    @Option(name: .shortAndLong, help: "Идентификатор модели (обязательный).")
    var model: String

    @Option(name: .shortAndLong, help: "Промпт одной строкой. Либо используйте --input-file / stdin.")
    var prompt: String?

    @Option(name: .long, help: "Путь к файлу с промптом.")
    var inputFile: String?

    @Flag(name: .shortAndLong, help: "Включить потоковый вывод.")
    var stream: Bool = false

    @Flag(name: .long, help: "Вывести результат в формате JSON (final result).")
    var jsonOutput: Bool = false

    @Flag(name: .long, help: "Читать промпт из стандартного ввода.")
    var stdin: Bool = false

    @MainActor
    func run() async throws {
        try await global.bootstrapContext()

        guard let context = PlaygroundContext.shared else {
            throw ContextError.missingRootContext
        }

        await context.logger.verbose("Инициализация команды chat")

        let inputText = try await resolvePromptText(logger: context.logger)
        let chosenProvider = provider ?? context.configuration.defaultProvider

        let languageModel = try ProviderFactory.makeLanguageModel(
            provider: chosenProvider,
            modelId: model,
            configuration: context.configuration,
            logger: context.logger
        )

        if stream {
            try await runStreaming(
                model: languageModel,
                promptText: inputText,
                logger: context.logger
            )
        } else {
            try await runSynchronous(
                model: languageModel,
                promptText: inputText,
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
            await logger.verbose("Читаю промпт из stdin...")
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
        jsonOutput: Bool,
        logger: PlaygroundLogger
    ) async throws {
        let callOptions = try await buildCallOptions(for: model, promptText: promptText)
        let response = try await model.doGenerate(options: callOptions)

        let text = extractText(from: response.content)

        if jsonOutput {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let payload = PlaygroundJSONResult(
                text: text,
                usage: response.usage,
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

    private func runStreaming(
        model: any LanguageModelV3,
        promptText: String,
        logger: PlaygroundLogger
    ) async throws {
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
                await logger.verbose("Пропущен потоковый chunk: \(part)")
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
            case .toolCall, .toolResult, .reasoning, .file, .source:
                continue
            }
        }
        return output
    }
}

private struct PlaygroundJSONResult: Codable {
    let text: String
    let usage: LanguageModelUsage
    let finishReason: FinishReason
    let warnings: [CallWarning]?
}

enum ContextError: LocalizedError {
    case missingRootContext
    case unsupportedProvider(String)
    case missingPrompt
    case missingAPIKey(provider: String)

    var errorDescription: String? {
        switch self {
        case .missingRootContext:
            return "Внутренняя ошибка: контекст CLI не инициализирован. Запустите команду через `swift run playground ...`."
        case .unsupportedProvider(let provider):
            return "Провайдер \(provider) пока не поддерживается."
        case .missingPrompt:
            return "Укажите промпт через --prompt, --input-file или --stdin."
        case .missingAPIKey(let provider):
            return "Не найден API ключ для провайдера \(provider). Добавьте его в переменные окружения или .env."
        }
    }
}
