/**
 Zod Constraints Test with GPT-4.1

 Tests if GPT-4.1 respects JSON Schema constraints (minLength/maxLength) without prompt hints.
 Equivalent to: external/vercel-ai-sdk/examples/ai-core/test-constraints.mjs
 */

import Foundation
import SwiftAISDK
import OpenAIProvider
import AISDKJSONSchema
import AISDKZodAdapter
import AISDKProviderUtils
import ExamplesCore

struct User: Codable, Sendable {
    let name: String
    let bio: String
    let age: Int
}

@main
struct ZodConstraintsTest: CLIExample {
    static let name = "Zod Constraints Test (GPT-4.1)"
    static let description = "Test if GPT-4.1 respects minLength/maxLength constraints"

    static func run() async throws {
        Logger.section("Testing Zod constraints (min/max) with GPT-4.1")

        // Create Zod schema with constraints (same as TypeScript test)
        let userSchema = z.object([
            "name": z.string(minLength: 3, maxLength: 20),
            "bio": z.string(minLength: 10, maxLength: 50),       // ← Testing this constraint
            "age": z.number(min: 18, max: 100, integer: true)
        ])

        let schema: FlexibleSchema<User> = .fromZod(User.self, zod: userSchema)

        Logger.info("Schema created with constraints:")
        Logger.info("  name: minLength=3, maxLength=20")
        Logger.info("  bio: minLength=10, maxLength=50")
        Logger.info("  age: min=18, max=100, integer")
        Logger.separator()

        do {
            let result = try await generateObject(
                model: openai("gpt-4.1"),
                schema: schema,
                prompt: "Generate a user profile for John Doe, age 25",  // NO hints about constraints!
                schemaName: "user",
                schemaDescription: "A user profile"
            )

            Logger.success("✅ Generated object:")
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let jsonData = try encoder.encode(result.object)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                print(jsonString)
            }

            Logger.separator()
            Logger.info("📊 Validation:")
            Logger.info("  name length: \(result.object.name.count) (should be 3-20)")
            Logger.info("  bio length: \(result.object.bio.count) (should be 10-50)")
            Logger.info("  age: \(result.object.age) (should be 18-100)")

            // Check if constraints were respected
            let bioLength = result.object.bio.count
            if bioLength > 50 {
                Logger.warning("⚠️  Bio exceeded maxLength: \(bioLength) > 50")
                Logger.info("This means GPT-4.1 did NOT respect the constraint during generation")
            } else {
                Logger.success("✅ Bio respected maxLength constraint")
            }

        } catch let error as NoObjectGeneratedError {
            Logger.error("❌ Error: \(error.message)")

            if let text = error.text {
                Logger.info("\nReturned text (first 200 chars):")
                let preview = String(text.prefix(200))
                print(preview + (text.count > 200 ? "..." : ""))
            }

            if let cause = error.cause {
                Logger.info("\nCause (validation error):")
                print(cause)
                Logger.separator()
                Logger.info("💡 This is EXPECTED behavior:")
                Logger.info("   - GPT-4.1 generates content freely")
                Logger.info("   - Zod validates AFTER generation")
                Logger.info("   - Constraints are CLIENT-SIDE validation, not enforced by model")
            }

        } catch {
            Logger.error("❌ Unexpected error: \(error)")
        }
    }
}
