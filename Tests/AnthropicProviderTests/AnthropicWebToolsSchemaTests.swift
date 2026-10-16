import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import AnthropicProvider

@Suite("Anthropic web tools schemas")
struct AnthropicWebToolsSchemaTests {
    @Test("web fetch validates nullable metadata and document source format", arguments: [20250910, 20260209, 20260318])
    func webFetchDocuments(version: Int) async throws {
        let tool: Tool
        switch version {
        case 20250910: tool = anthropicTools.webFetch20250910()
        case 20260209: tool = anthropicTools.webFetch20260209()
        default: tool = anthropicTools.webFetch20260318()
        }
        let input = JSONValue.object(["url": .string("https://example.com")])
        let inputSchema = tool.inputSchema.resolve()
        guard case .success(let validatedInput) = await inputSchema.validate(input) else {
            Issue.record("Expected a valid web fetch URL")
            return
        }
        #expect(validatedInput == input)
        let outputSchema = try #require(tool.outputSchema)
        let schema = outputSchema.resolve()
        let result: JSONValue = .object([
            "type": .string("web_fetch_result"),
            "url": .string("https://example.com"),
            "retrievedAt": .null,
            "content": .object([
                "type": .string("document"),
                "title": .null,
                "source": .object(["type": .string("text"), "mediaType": .string("text/plain"), "data": .string("document")]),
            ]),
        ])
        guard case .success(let validated) = await schema.validate(result) else {
            Issue.record("Expected fetched content with nullable metadata")
            return
        }
        #expect(validated == result)
        let invalid: JSONValue = .object([
            "type": .string("web_fetch_result"),
            "url": .string("https://example.com"),
            "retrievedAt": .null,
            "content": .object([
                "type": .string("document"),
                "title": .null,
                "source": .object(["type": .string("text"), "mediaType": .string("application/pdf"), "data": .string("document")]),
            ]),
        ])
        guard case .failure = await schema.validate(invalid) else {
            Issue.record("Expected document media type mismatch rejection")
            return
        }
    }

    @Test("web search preserves encrypted citation data and requires it", arguments: [20250305, 20260209, 20260318])
    func webSearchCitations(version: Int) async throws {
        let tool: Tool
        switch version {
        case 20250305: tool = anthropicTools.webSearch20250305()
        case 20260209: tool = anthropicTools.webSearch20260209()
        default: tool = anthropicTools.webSearch20260318()
        }
        let outputSchema = try #require(tool.outputSchema)
        let schema = outputSchema.resolve()
        var entry: [String: JSONValue] = [
            "type": .string("web_search_result"),
            "url": .string("https://example.com"),
            "title": .null,
            "pageAge": .null,
            "encryptedContent": .string("opaque-citation"),
        ]
        let result = JSONValue.array([.object(entry)])
        guard case .success(let validated) = await schema.validate(result) else {
            Issue.record("Expected a valid encrypted search citation")
            return
        }
        #expect(validated == result)
        entry.removeValue(forKey: "encryptedContent")
        guard case .failure = await schema.validate(JSONValue.array([.object(entry)])) else {
            Issue.record("Expected citation result without encrypted content rejection")
            return
        }
    }

    @Test("latest web tool arguments reject unsupported response inclusion")
    func responseInclusionValidation() async throws {
        let fetchSchema = anthropicWebFetch20260318ArgsSchema.resolve()
        let searchSchema = anthropicWebSearch20260318ArgsSchema.resolve()
        guard case .failure = await fetchSchema.validate(["responseInclusion": "summary"]) else {
            Issue.record("Expected unsupported fetch response inclusion rejection")
            return
        }
        guard case .failure = await searchSchema.validate(["responseInclusion": "summary"]) else {
            Issue.record("Expected unsupported search response inclusion rejection")
            return
        }
        guard case .failure = await fetchSchema.validate(["useCache": NSNull()]) else {
            Issue.record("Expected an explicit null cache control to be rejected")
            return
        }
    }
}
