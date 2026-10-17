import Testing
import AISDKProvider
import AISDKProviderUtils
import OpenAIProvider

@Suite("Code interpreter output validation")
struct OpenAICodeInterpreterOutputSchemaTests {
    @Test("Code interpreter variants require their own output data", arguments: ["logs", "image"])
    func requiredOutput(type: String) async throws {
        let schema = try #require(openaiTools.codeInterpreter().outputSchema)
        await #expect(throws: TypeValidationError.self) {
            try await validateTypes(ValidateTypesOptions(value: JSONValue.object([
                "outputs": .array([.object(["type": .string(type)])])
            ]), schema: schema))
        }
    }
}
