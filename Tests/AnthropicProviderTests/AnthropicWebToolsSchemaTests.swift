import Testing
import AISDKProvider
@testable import AnthropicProvider

@Suite("Anthropic web tools schemas")
struct AnthropicWebToolsSchemaTests {
    @Test("web_fetch_20250910 tool input/output schemas match upstream shape")
    func webFetch20250910ToolSchemas() async throws {
        let tool = anthropicWebFetch20250910()

        let input = try await tool.inputSchema.resolve().jsonSchema()
        let output = try await tool.outputSchema?.resolve().jsonSchema()

        #expect(input == .object([
            "type": .string("object"),
            "required": .array([.string("url")]),
            "properties": .object([
                "url": .object(["type": .string("string")])
            ]),
            "additionalProperties": .bool(false),
        ]))

        #expect(output == .object([
            "type": .string("object"),
            "required": .array([.string("type"), .string("url"), .string("content"), .string("retrievedAt")]),
            "additionalProperties": .bool(false),
            "properties": .object([
                "type": .object(["const": .string("web_fetch_result")]),
                "url": .object(["type": .string("string")]),
                "content": .object([
                    "type": .string("object"),
                    "required": .array([.string("type"), .string("title"), .string("source")]),
                    "additionalProperties": .bool(false),
                    "properties": .object([
                        "type": .object(["const": .string("document")]),
                        "title": .object(["type": .array([.string("string"), .string("null")])]),
                        "citations": .object([
                            "type": .string("object"),
                            "required": .array([.string("enabled")]),
                            "additionalProperties": .bool(false),
                            "properties": .object([
                                "enabled": .object(["type": .string("boolean")])
                            ]),
                        ]),
                        "source": .object([
                            "oneOf": .array([
                                .object([
                                    "type": .string("object"),
                                    "required": .array([.string("type"), .string("mediaType"), .string("data")]),
                                    "additionalProperties": .bool(false),
                                    "properties": .object([
                                        "type": .object(["const": .string("base64")]),
                                        "mediaType": .object(["const": .string("application/pdf")]),
                                        "data": .object(["type": .string("string")]),
                                    ]),
                                ]),
                                .object([
                                    "type": .string("object"),
                                    "required": .array([.string("type"), .string("mediaType"), .string("data")]),
                                    "additionalProperties": .bool(false),
                                    "properties": .object([
                                        "type": .object(["const": .string("text")]),
                                        "mediaType": .object(["const": .string("text/plain")]),
                                        "data": .object(["type": .string("string")]),
                                    ]),
                                ]),
                            ])
                        ]),
                    ]),
                ]),
                "retrievedAt": .object(["type": .array([.string("string"), .string("null")])]),
            ]),
        ]))
    }

    @Test("web_search_20250305 tool input/output schemas match upstream shape")
    func webSearch20250305ToolSchemas() async throws {
        let tool = anthropicWebSearch20250305()

        let input = try await tool.inputSchema.resolve().jsonSchema()
        let output = try await tool.outputSchema?.resolve().jsonSchema()

        #expect(input == .object([
            "type": .string("object"),
            "required": .array([.string("query")]),
            "properties": .object([
                "query": .object(["type": .string("string")])
            ]),
            "additionalProperties": .bool(false),
        ]))

        #expect(output == .object([
            "type": .string("array"),
            "items": .object([
                "type": .string("object"),
                "required": .array([
                    .string("url"),
                    .string("title"),
                    .string("pageAge"),
                    .string("encryptedContent"),
                    .string("type"),
                ]),
                "additionalProperties": .bool(false),
                "properties": .object([
                    "url": .object(["type": .string("string")]),
                    "title": .object(["type": .array([.string("string"), .string("null")])]),
                    "pageAge": .object(["type": .array([.string("string"), .string("null")])]),
                    "encryptedContent": .object(["type": .string("string")]),
                    "type": .object(["const": .string("web_search_result")]),
                ]),
            ]),
        ]))
    }
}

