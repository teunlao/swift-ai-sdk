import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import OpenAIProvider

@Suite("OpenAIError")
struct OpenAIErrorTests {
    @Test("openAIErrorDataSchema parses nested payloads")
    func testOpenAIErrorSchemaParsesNestedPayload() async throws {
        let errorText = #"""
{"error":{"message":"{\n  \"error\": {\n    \"code\": 429,\n    \"message\": \"Resource has been exhausted (e.g. check quota).\",\n    \"status\": \"RESOURCE_EXHAUSTED\"\n  }\n}\n","code":429}}
"""#

        let result = await safeParseJSON(
            ParseJSONWithSchemaOptions(text: errorText, schema: openAIErrorDataSchema)
        )

        switch result {
        case .success(let value, let raw):
            #expect(value.error.message.contains("Resource has been exhausted"))
            #expect(value.error.code == .number(429))
            if let rawObject = raw as? [String: Any] {
                #expect(rawObject["error"] != nil)
            } else {
                Issue.record("Expected raw object")
            }
        case .failure(let error, _):
            Issue.record("Expected successful parse of OpenAI error payload: \(error)")
        }
    }
}
