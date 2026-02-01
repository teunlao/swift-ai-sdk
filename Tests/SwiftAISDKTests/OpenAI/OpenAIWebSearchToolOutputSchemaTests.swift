import Testing
@testable import AISDKProviderUtils
@testable import OpenAIProvider

@Suite("OpenAI Web Search Tool Output Schemas")
struct OpenAIWebSearchToolOutputSchemaTests {
    @Test("web_search tool output schema validates expected shapes")
    func webSearchOutputSchema() async {
        let tool = openaiTools.webSearch()
        guard let schema = tool.outputSchema else {
            Issue.record("Expected outputSchema for openai.web_search tool")
            return
        }

        let valid: [String: Any] = [
            "action": [
                "type": "search",
                "query": "hello"
            ],
            "sources": [
                ["type": "url", "url": "https://example.com"]
            ]
        ]

        switch await safeValidateTypes(ValidateTypesOptions(value: valid, schema: schema)) {
        case .success:
            break
        case .failure(let error, _):
            Issue.record("Expected output to validate, got error: \(error)")
        }

        let invalid: [String: Any] = [
            "action": [:]
        ]

        switch await safeValidateTypes(ValidateTypesOptions(value: invalid, schema: schema)) {
        case .success:
            Issue.record("Expected output validation to fail")
        case .failure:
            break
        }
    }

    @Test("web_search_preview tool output schema validates expected shapes")
    func webSearchPreviewOutputSchema() async {
        let tool = openaiTools.webSearchPreview()
        guard let schema = tool.outputSchema else {
            Issue.record("Expected outputSchema for openai.web_search_preview tool")
            return
        }

        let valid: [String: Any] = [
            "action": [
                "type": "openPage",
                "url": "https://example.com"
            ]
        ]

        switch await safeValidateTypes(ValidateTypesOptions(value: valid, schema: schema)) {
        case .success:
            break
        case .failure(let error, _):
            Issue.record("Expected output to validate, got error: \(error)")
        }

        let invalid: [String: Any] = [
            "action": [:]
        ]

        switch await safeValidateTypes(ValidateTypesOptions(value: invalid, schema: schema)) {
        case .success:
            Issue.record("Expected output validation to fail")
        case .failure:
            break
        }
    }
}
