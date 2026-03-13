import Foundation
import Testing
@testable import AISDKProviderUtils
@testable import OpenAIProvider

@Suite("OpenAI Code Interpreter Output Schema")
struct OpenAICodeInterpreterOutputSchemaTests {
    @Test("code_interpreter output schema validates discriminated union items")
    func codeInterpreterOutputSchema() async {
        let tool = openaiTools.codeInterpreter()
        guard let schema = tool.outputSchema else {
            Issue.record("Expected outputSchema for openai.code_interpreter tool")
            return
        }

        let valid: [String: Any] = [
            "outputs": [
                [
                    "type": "logs",
                    "logs": "print('hello')"
                ],
                [
                    "type": "image",
                    "url": "https://example.com/image.png"
                ]
            ]
        ]

        switch await safeValidateTypes(ValidateTypesOptions(value: valid, schema: schema)) {
        case .success:
            break
        case .failure(let error, _):
            Issue.record("Expected valid code interpreter output, got error: \(error)")
        }

        let invalidMissingLogs: [String: Any] = [
            "outputs": [
                [
                    "type": "logs"
                ]
            ]
        ]

        switch await safeValidateTypes(ValidateTypesOptions(value: invalidMissingLogs, schema: schema)) {
        case .success:
            Issue.record("Expected logs item without logs to fail validation")
        case .failure:
            break
        }

        let invalidMissingURL: [String: Any] = [
            "outputs": [
                [
                    "type": "image"
                ]
            ]
        ]

        switch await safeValidateTypes(ValidateTypesOptions(value: invalidMissingURL, schema: schema)) {
        case .success:
            Issue.record("Expected image item without url to fail validation")
        case .failure:
            break
        }

        let invalidCrossedFields: [String: Any] = [
            "outputs": [
                [
                    "type": "logs",
                    "url": "https://example.com/not-allowed.png"
                ]
            ]
        ]

        switch await safeValidateTypes(ValidateTypesOptions(value: invalidCrossedFields, schema: schema)) {
        case .success:
            Issue.record("Expected logs item with image-only field to fail validation")
        case .failure:
            break
        }
    }
}
