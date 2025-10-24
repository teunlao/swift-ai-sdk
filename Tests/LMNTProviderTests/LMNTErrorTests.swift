import Foundation
import Testing
@testable import AISDKProviderUtils
@testable import LMNTProvider

@Suite("LMNTErrorSchema")
struct LMNTErrorTests {
    @Test("should parse LMNT resource exhausted error")
    func parseResourceExhausted() async throws {
        let errorText = """
{"error":{"message":"{\\n  \\"error\\": {\\n    \\"code\\": 429,\\n    \\"message\\": \\"Resource has been exhausted (e.g. check quota).\\",\\n    \\"status\\": \\"RESOURCE_EXHAUSTED\\"\\n  }\\n}\\n","code":429}}
"""

        let result = await safeParseJSON(
            ParseJSONWithSchemaOptions(text: errorText, schema: lmntErrorDataSchema)
        )

        switch result {
        case .success(let value, _):
            #expect(value.error.code == 429)
            #expect(value.error.message.contains("RESOURCE_EXHAUSTED"))
        case .failure:
            Issue.record("Expected schema to parse error JSON")
        }
    }
}
