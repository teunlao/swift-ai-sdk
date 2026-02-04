import Foundation
import Testing
@testable import AISDKProviderUtils
@testable import RevAIProvider

@Suite("RevAIError")
struct RevAIErrorTests {
    @Test("revaiErrorDataSchema parses resource exhausted error")
    func parsesResourceExhaustedError() async throws {
        let error = #"""

{"error":{"message":"{\n  \"error\": {\n    \"code\": 429,\n    \"message\": \"Resource has been exhausted (e.g. check quota).\",\n    \"status\": \"RESOURCE_EXHAUSTED\"\n  }\n}\n","code":429}}

"""#

        let result = await safeParseJSON(
            ParseJSONWithSchemaOptions(text: error, schema: revaiErrorDataSchema)
        )

        switch result {
        case .success(let value, let rawValue):
            let expectedMessage = """
            {
              "error": {
                "code": 429,
                "message": "Resource has been exhausted (e.g. check quota).",
                "status": "RESOURCE_EXHAUSTED"
              }
            }

            """

            #expect(value == RevAIErrorData(
                error: .init(message: expectedMessage, code: 429)
            ))

            if let dict = rawValue as? [String: Any],
               let errorDict = dict["error"] as? [String: Any] {
                let message = errorDict["message"] as? String
                let code = (errorDict["code"] as? NSNumber)?.intValue
                #expect(message == expectedMessage)
                #expect(code == 429)
            } else {
                Issue.record("rawValue is not a dictionary")
            }
        case .failure(let error, _):
            Issue.record("Expected success, got error: \(error)")
        }
    }
}
