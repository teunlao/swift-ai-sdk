#!/usr/bin/env swift

// Простой пример использования tools с Swift AI SDK
// Запуск: swift examples/tool-example.swift

import Foundation

#if canImport(SwiftAISDK)
import SwiftAISDK
import AISDKProvider
import AISDKProviderUtils
import OpenAIProvider
#else
print("❌ Ошибка: SwiftAISDK не найден. Используйте Package.swift для сборки.")
exit(1)
#endif

// MARK: - Простой weather tool

func createWeatherTool() -> Tool {
    tool(
        description: "Get the weather in a location",
        inputSchema: .jsonSchema(
            .object([
                "$schema": .string("http://json-schema.org/draft-07/schema#"),
                "type": .string("object"),
                "properties": .object([
                    "location": .object([
                        "type": .string("string"),
                        "description": .string("The location to get the weather for")
                    ])
                ]),
                "required": .array([.string("location")]),
                "additionalProperties": .bool(false)
            ])
        ),
        execute: { input, _ in
            // Извлекаем location из input
            guard case .object(let obj) = input,
                  case .string(let location) = obj["location"] else {
                return .value(.object(["error": .string("Invalid input")]))
            }

            // Симулируем получение погоды
            let temperature = 72 + Int.random(in: -10...10)

            let result: JSONValue = .object([
                "location": .string(location),
                "temperature": .number(Double(temperature)),
                "unit": .string("fahrenheit")
            ])

            return .value(result)
        }
    )
}

// MARK: - Calculator tool

func createCalculatorTool() -> Tool {
    tool(
        description: "Perform basic math operations",
        inputSchema: .jsonSchema(
            .object([
                "$schema": .string("http://json-schema.org/draft-07/schema#"),
                "type": .string("object"),
                "properties": .object([
                    "operation": .object([
                        "type": .string("string"),
                        "enum": .array([.string("add"), .string("subtract"), .string("multiply"), .string("divide")]),
                        "description": .string("Math operation to perform")
                    ]),
                    "a": .object([
                        "type": .string("number"),
                        "description": .string("First number")
                    ]),
                    "b": .object([
                        "type": .string("number"),
                        "description": .string("Second number")
                    ])
                ]),
                "required": .array([.string("operation"), .string("a"), .string("b")]),
                "additionalProperties": .bool(false)
            ])
        ),
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
            case "divide": result = b != 0 ? a / b : 0
            default: result = 0
            }

            return .value(.object([
                "result": .number(result),
                "operation": .string(op)
            ]))
        }
    )
}

// MARK: - Main

@main
struct ToolExample {
    static func main() async throws {
        print("🔧 Swift AI SDK - Tool Example\n")

        // Проверяем API ключ
        guard let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"],
              !apiKey.isEmpty else {
            print("❌ Ошибка: OPENAI_API_KEY не установлен")
            print("   Установите: export OPENAI_API_KEY='your-key'")
            print("   Или используйте .env файл")
            exit(1)
        }

        // Создаем OpenAI провайдер
        let settings = OpenAIProviderSettings(apiKey: apiKey)
        let provider = createOpenAIProvider(settings: settings)
        let model = provider.languageModel(modelId: "gpt-4o-mini")

        // Создаем набор инструментов
        let tools: ToolSet = [
            "getWeather": createWeatherTool(),
            "calculate": createCalculatorTool()
        ]

        print("📝 Промпт: 'What is the weather in San Francisco? Also calculate 25 * 4'")
        print("\n⏳ Отправка запроса...\n")

        // Вызываем generateText с инструментами
        let result: DefaultGenerateTextResult<JSONValue> = try await generateText(
            model: .v3(model),
            tools: tools,
            prompt: "What is the weather in San Francisco? Also calculate 25 * 4"
        )

        // Выводим результаты
        print("📊 Результаты:\n")
        print("Finish reason: \(result.finishReason.rawValue)")
        print("Steps: \(result.steps.count)")
        print("Usage: \(result.usage.totalTokens) tokens")
        print("\n📄 Контент:\n")

        for (index, content) in result.content.enumerated() {
            switch content {
            case .text(let text, _):
                print("[\(index)] 💬 Text: \(text)")

            case .toolCall(let call, _):
                print("[\(index)] 🔧 Tool Call:")
                print("    - Name: \(call.toolName)")
                print("    - ID: \(call.toolCallId)")
                print("    - Input: \(call.input)")

            case .toolResult(let resultContent, _):
                print("[\(index)] ✅ Tool Result:")
                print("    - Tool: \(resultContent.toolName)")
                print("    - Call ID: \(resultContent.toolCallId)")
                print("    - Output: \(resultContent.output)")
                if let error = resultContent.error {
                    print("    - Error: \(error)")
                }

            default:
                print("[\(index)] Other: \(content)")
            }
        }

        print("\n✅ Пример завершен!")
    }
}
