import ExamplesCore
import Foundation
import OpenAIProvider
import SwiftAISDK

// MARK: - Codable Payloads Used In README Snippets

private enum MathOperation: String, Codable, Sendable, CaseIterable {
    case add
    case mul
}

private struct CalculatorInput: Codable, Sendable {
    let op: MathOperation
    let a: Double
    let b: Double
}

// MARK: - JSONValue ↔︎ Codable Bridge Helpers

private enum JSONValueDecodingError: LocalizedError {
    case invalidJSONObject

    var errorDescription: String? {
        switch self {
        case .invalidJSONObject:
            return "JSONValue payload is not a valid JSON object for decoding."
        }
    }
}

private func decodeJSONValue<T: Decodable>(_ type: T.Type, from value: JSONValue) throws -> T {
    let foundation = try value.toFoundationObject()

    guard JSONSerialization.isValidJSONObject(foundation) else {
        throw JSONValueDecodingError.invalidJSONObject
    }

    let data = try JSONSerialization.data(withJSONObject: foundation)
    let decoder = JSONDecoder()
    return try decoder.decode(T.self, from: data)
}

private extension JSONValue {
    func toFoundationObject() throws -> Any {
        switch self {
        case .null:
            return NSNull()
        case .bool(let value):
            return value
        case .number(let value):
            return value
        case .string(let value):
            return value
        case .array(let values):
            return try values.map { try $0.toFoundationObject() }
        case .object(let dictionary):
            var result: [String: Any] = [:]
            result.reserveCapacity(dictionary.count)
            for (key, value) in dictionary {
                result[key] = try value.toFoundationObject()
            }
            return result
        }
    }
}

// MARK: - Example Runner

@main
struct READMEExamples: CLIExample {
    static let name = "README Tool Examples"
    static let description = "Validates README code snippets using Codable tool schemas."

    static func run() async throws {
        let schema = FlexibleSchema.auto(CalculatorInput.self)
        let jsonSchemaValue = try await schema.resolve().jsonSchema()
        Logger.info("Generated JSON schema for CalculatorInput:")
        Helpers.printJSON(jsonSchemaValue)
        let toolSchema = FlexibleSchema(jsonSchema(jsonSchemaValue))

        let calculate = tool(
            description: "Basic math",
            inputSchema: toolSchema,
            execute: { input, _ in
                let payload = try decodeJSONValue(CalculatorInput.self, from: input)
                let result: Double
                switch payload.op {
                case .add:
                    result = payload.a + payload.b
                case .mul:
                    result = payload.a * payload.b
                }

                return .value(.object([
                    "result": .number(result)
                ]))
            }
        )

        let response = try await generateText(
            model: openai("gpt-5"),
            tools: ["calculate": calculate],
            prompt: "Use tools to compute 25*4."
        )

        Logger.success("README tool example finished: \(response.text)")
    }
}
