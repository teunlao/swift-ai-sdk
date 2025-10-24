import Testing
@testable import SwiftAISDK
import AISDKProvider
import AISDKProviderUtils

@Suite("injectJSONInstruction")
struct InjectJSONInstructionTests {
    @Test("includes prompt schema and suffix")
    func includesPromptSchemaAndSuffix() throws {
        let schema: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([
                "content": .object(["type": .string("string")])
            ])
        ])

        let result = injectJSONInstruction(
            prompt: "Generate",
            schema: schema
        )

        #expect(result.contains("Generate"))
        #expect(result.contains("JSON schema:"))
        #expect(result.contains("You MUST answer with a JSON object"))
    }

    @Test("respects custom prefix and suffix")
    func respectsCustomPrefixAndSuffix() throws {
        let schema: JSONValue = .object(["type": .string("string")])
        let result = injectJSONInstruction(
            prompt: nil,
            schema: schema,
            schemaPrefix: "PREFIX",
            schemaSuffix: "SUFFIX"
        )

        #expect(result.hasPrefix("PREFIX"))
        #expect(result.hasSuffix("SUFFIX"))
    }

    @Test("falls back to json suffix without schema")
    func fallsBackWithoutSchema() throws {
        let result = injectJSONInstruction(
            prompt: "Hello",
            schema: nil
        )

        #expect(result.contains("You MUST answer with JSON."))
    }
}
