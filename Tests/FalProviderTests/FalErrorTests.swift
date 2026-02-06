import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import FalProvider

@Suite("FalError")
struct FalErrorTests {
    @Test("parses resource exhausted error envelope")
    func parsesResourceExhaustedErrorEnvelope() async throws {
        let errorJSON = """
        {"error":{"message":"{\\n  \\"error\\": {\\n    \\"code\\": 429,\\n    \\"message\\": \\"Resource has been exhausted (e.g. check quota).\\",\\n    \\"status\\": \\"RESOURCE_EXHAUSTED\\"\\n  }\\n}\\n","code":429}}
        """

        let schema = FlexibleSchema(
            Schema<FalErrorPayload>.codable(
                FalErrorPayload.self,
                jsonSchema: .object(["type": .string("object")])
            )
        )

        let result = await safeParseJSON(
            ParseJSONWithSchemaOptions(text: errorJSON, schema: schema)
        )

        switch result {
        case .success(let value, _):
            #expect(value.error.code == 429)
            #expect(value.error.message.contains("Resource has been exhausted"))
            #expect(value.error.message.contains("\"RESOURCE_EXHAUSTED\""))
        case .failure(let error, _):
            Issue.record("Expected successful parse, got error: \(error)")
        }
    }
}
