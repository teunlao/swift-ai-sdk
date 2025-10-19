import AISDKZodAdapter
import Foundation
import SwiftAISDK

@main
struct ZodGenerateObjectExample {
    static func main() async {
        print("🧩 Zod → JSON Schema → Schema → generateObject example")

        struct Repo: Codable, Sendable {
            let name: String
            let stars: Int
        }

        let repoZod = z.object([
            "name": z.string(minLength: 1),
            "stars": z.number(min: 0, integer: true),
        ])

        let repoSchema: Schema<Repo> = schemaFromZod3(Repo.self, zod: repoZod)

        do {
            let model: LanguageModel = .openAI(.responses("gpt-4.1-mini"))

            // Вариант 1: Zod DSL → JSON Schema → Schema<Repo>
            let result = try await generateObject(
                model: model,
                schema: repoSchema,
                prompt:
                    "Return a JSON object with fields: name (Swift repo), stars (non-negative integer)."
            )

            print("✅ Object:", result.object)
            print("📊 Usage:", result.usage)

            // Вариант 2: Без Zod (чистый JSON Schema + Schema.codable)
            let plainJSONSchema: JSONValue = .object([
                "type": .string("object"),
                "properties": .object([
                    "name": .object(["type": .string("string"), "minLength": .number(1)]),
                    "stars": .object(["type": .string("integer"), "minimum": .number(0)]),
                ]),
                "required": .array([.string("name"), .string("stars")]),
                "additionalProperties": .bool(false),
            ])
            let plainSchema: Schema<Repo> = Schema.codable(Repo.self, jsonSchema: plainJSONSchema)

            let resultPlain = try await generateObject(
                model: model,
                schema: plainSchema,
                prompt:
                    "Return a JSON object with fields: name (Swift repo), stars (non-negative integer)."
            )

            print("✅ (no-zod) Object:", resultPlain.object)
            print("📊 (no-zod) Usage:", resultPlain.usage)
        } catch {
            print("❌ Error:", error)
        }
    }
}
