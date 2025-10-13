/**
 Tests for MCP protocol types encoding/decoding.

 Tests encoding/decoding round-trips for all MCP types to ensure 100% parity
 with upstream TypeScript behavior.
 */

import Foundation
import Testing
@testable import SwiftAISDK

@Suite("MCP Types")
struct MCPTypesTests {

    // MARK: - Protocol Versioning Tests

    @Test("Protocol version constants match upstream")
    func testProtocolVersions() {
        #expect(latestProtocolVersion == "2025-06-18")
        #expect(supportedProtocolVersions == ["2025-06-18", "2025-03-26", "2024-11-05"])
    }

    // MARK: - Configuration Tests

    @Test("Configuration encoding/decoding")
    func testConfigurationCoding() throws {
        let config = Configuration(name: "test-client", version: "1.0.0")

        let encoded = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(Configuration.self, from: encoded)

        #expect(decoded.name == "test-client")
        #expect(decoded.version == "1.0.0")
    }

    @Test("Configuration JSON format")
    func testConfigurationJSONFormat() throws {
        let config = Configuration(name: "test-client", version: "1.0.0")
        let encoded = try JSONEncoder().encode(config)
        let json = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]

        #expect(json["name"] as? String == "test-client")
        #expect(json["version"] as? String == "1.0.0")
    }

    // MARK: - BaseParams Tests

    @Test("BaseParams with meta encoding/decoding")
    func testBaseParamsWithMeta() throws {
        let params = BaseParams(meta: ["key": .string("value")])

        let encoded = try JSONEncoder().encode(params)
        let decoded = try JSONDecoder().decode(BaseParams.self, from: encoded)

        #expect(decoded.meta != nil)
        #expect(decoded.meta?["key"] == .string("value"))
    }

    @Test("BaseParams without meta")
    func testBaseParamsWithoutMeta() throws {
        let params = BaseParams(meta: nil)

        let encoded = try JSONEncoder().encode(params)
        let decoded = try JSONDecoder().decode(BaseParams.self, from: encoded)

        #expect(decoded.meta == nil)
    }

    @Test("BaseParams _meta field mapping")
    func testBaseParamsMetaFieldMapping() throws {
        let params = BaseParams(meta: ["test": .number(42)])
        let encoded = try JSONEncoder().encode(params)
        let json = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]

        // Should encode as "_meta", not "meta"
        #expect(json["_meta"] != nil)
        #expect(json["meta"] == nil)
    }

    // MARK: - Request Tests

    @Test("Request encoding/decoding")
    func testRequestCoding() throws {
        let request = Request(
            method: "tools/list",
            params: BaseParams(meta: ["cursor": .string("abc123")])
        )

        let encoded = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(Request.self, from: encoded)

        #expect(decoded.method == "tools/list")
        #expect(decoded.params?.meta?["cursor"] == .string("abc123"))
    }

    // MARK: - ServerCapabilities Tests

    @Test("ServerCapabilities with all fields")
    func testServerCapabilitiesComplete() throws {
        let capabilities = ServerCapabilities(
            experimental: ["feature": .bool(true)],
            logging: ["level": .string("debug")],
            prompts: ServerCapabilities.PromptsCapabilities(listChanged: true),
            resources: ServerCapabilities.ResourcesCapabilities(subscribe: true, listChanged: false),
            tools: ServerCapabilities.ToolsCapabilities(listChanged: true)
        )

        let encoded = try JSONEncoder().encode(capabilities)
        let decoded = try JSONDecoder().decode(ServerCapabilities.self, from: encoded)

        #expect(decoded.experimental?["feature"] == .bool(true))
        #expect(decoded.logging?["level"] == .string("debug"))
        #expect(decoded.prompts?.listChanged == true)
        #expect(decoded.resources?.subscribe == true)
        #expect(decoded.resources?.listChanged == false)
        #expect(decoded.tools?.listChanged == true)
    }

    @Test("ServerCapabilities with minimal fields")
    func testServerCapabilitiesMinimal() throws {
        let capabilities = ServerCapabilities()

        let encoded = try JSONEncoder().encode(capabilities)
        let decoded = try JSONDecoder().decode(ServerCapabilities.self, from: encoded)

        #expect(decoded.experimental == nil)
        #expect(decoded.logging == nil)
        #expect(decoded.prompts == nil)
        #expect(decoded.resources == nil)
        #expect(decoded.tools == nil)
    }

    // MARK: - InitializeResult Tests

    @Test("InitializeResult encoding/decoding")
    func testInitializeResultCoding() throws {
        let result = InitializeResult(
            protocolVersion: "2025-06-18",
            capabilities: ServerCapabilities(
                tools: ServerCapabilities.ToolsCapabilities(listChanged: true)
            ),
            serverInfo: Configuration(name: "test-server", version: "1.0.0"),
            instructions: "Test instructions",
            meta: ["sessionId": .string("session123")]
        )

        let encoded = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(InitializeResult.self, from: encoded)

        #expect(decoded.protocolVersion == "2025-06-18")
        #expect(decoded.serverInfo.name == "test-server")
        #expect(decoded.instructions == "Test instructions")
        #expect(decoded.meta?["sessionId"] == .string("session123"))
    }

    // MARK: - MCPTool Tests

    @Test("MCPTool with schema encoding/decoding")
    func testMCPToolCoding() throws {
        let tool = MCPTool(
            name: "test-tool",
            description: "A test tool",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "arg": .object(["type": .string("string")])
                ])
            ])
        )

        let encoded = try JSONEncoder().encode(tool)
        let decoded = try JSONDecoder().decode(MCPTool.self, from: encoded)

        #expect(decoded.name == "test-tool")
        #expect(decoded.description == "A test tool")

        if case .object(let schema) = decoded.inputSchema,
           case .string(let type) = schema["type"] {
            #expect(type == "object")
        } else {
            Issue.record("Expected object schema with type field")
        }
    }

    @Test("MCPTool without description")
    func testMCPToolWithoutDescription() throws {
        let tool = MCPTool(
            name: "test-tool",
            inputSchema: .object(["type": .string("object")])
        )

        let encoded = try JSONEncoder().encode(tool)
        let decoded = try JSONDecoder().decode(MCPTool.self, from: encoded)

        #expect(decoded.name == "test-tool")
        #expect(decoded.description == nil)
    }

    // MARK: - ListToolsResult Tests

    @Test("ListToolsResult with pagination")
    func testListToolsResultWithPagination() throws {
        let result = ListToolsResult(
            tools: [
                MCPTool(name: "tool1", inputSchema: .object(["type": .string("object")])),
                MCPTool(name: "tool2", inputSchema: .object(["type": .string("object")]))
            ],
            nextCursor: "cursor123",
            meta: ["page": .number(1)]
        )

        let encoded = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(ListToolsResult.self, from: encoded)

        #expect(decoded.tools.count == 2)
        #expect(decoded.tools[0].name == "tool1")
        #expect(decoded.tools[1].name == "tool2")
        #expect(decoded.nextCursor == "cursor123")
        #expect(decoded.meta?["page"] == .number(1))
    }

    // MARK: - ToolContent Tests

    @Test("ToolContent text encoding/decoding")
    func testToolContentText() throws {
        let content = ToolContent.text(ToolContent.TextContent(text: "Hello"))

        let encoded = try JSONEncoder().encode(content)
        let decoded = try JSONDecoder().decode(ToolContent.self, from: encoded)

        if case .text(let textContent) = decoded {
            #expect(textContent.text == "Hello")
            #expect(textContent.type == "text")
        } else {
            Issue.record("Expected text content")
        }
    }

    @Test("ToolContent image encoding/decoding")
    func testToolContentImage() throws {
        let content = ToolContent.image(ToolContent.ImageContent(
            data: "base64data",
            mimeType: "image/png"
        ))

        let encoded = try JSONEncoder().encode(content)
        let decoded = try JSONDecoder().decode(ToolContent.self, from: encoded)

        if case .image(let imageContent) = decoded {
            #expect(imageContent.data == "base64data")
            #expect(imageContent.mimeType == "image/png")
            #expect(imageContent.type == "image")
        } else {
            Issue.record("Expected image content")
        }
    }

    @Test("ToolContent resource encoding/decoding")
    func testToolContentResource() throws {
        let content = ToolContent.resource(ToolContent.EmbeddedResource(
            resource: .text(uri: "file://test.txt", mimeType: "text/plain", text: "content")
        ))

        let encoded = try JSONEncoder().encode(content)
        let decoded = try JSONDecoder().decode(ToolContent.self, from: encoded)

        if case .resource(let embeddedResource) = decoded {
            #expect(embeddedResource.type == "resource")
            if case .text(let uri, let mimeType, let text) = embeddedResource.resource {
                #expect(uri == "file://test.txt")
                #expect(mimeType == "text/plain")
                #expect(text == "content")
            } else {
                Issue.record("Expected text resource")
            }
        } else {
            Issue.record("Expected resource content")
        }
    }

    @Test("ToolContent JSON type discrimination")
    func testToolContentTypeDiscrimination() throws {
        let textContent = ToolContent.text(ToolContent.TextContent(text: "test"))
        let encoded = try JSONEncoder().encode(textContent)
        let json = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]

        #expect(json["type"] as? String == "text")
        #expect(json["text"] as? String == "test")
    }

    // MARK: - ResourceContents Tests

    @Test("ResourceContents text encoding/decoding")
    func testResourceContentsText() throws {
        let resource = ResourceContents.text(
            uri: "file://test.txt",
            mimeType: "text/plain",
            text: "Hello, World!"
        )

        let encoded = try JSONEncoder().encode(resource)
        let decoded = try JSONDecoder().decode(ResourceContents.self, from: encoded)

        if case .text(let uri, let mimeType, let text) = decoded {
            #expect(uri == "file://test.txt")
            #expect(mimeType == "text/plain")
            #expect(text == "Hello, World!")
        } else {
            Issue.record("Expected text resource")
        }
    }

    @Test("ResourceContents blob encoding/decoding")
    func testResourceContentsBlob() throws {
        let resource = ResourceContents.blob(
            uri: "file://test.bin",
            mimeType: "application/octet-stream",
            blob: "base64encodeddata"
        )

        let encoded = try JSONEncoder().encode(resource)
        let decoded = try JSONDecoder().decode(ResourceContents.self, from: encoded)

        if case .blob(let uri, let mimeType, let blob) = decoded {
            #expect(uri == "file://test.bin")
            #expect(mimeType == "application/octet-stream")
            #expect(blob == "base64encodeddata")
        } else {
            Issue.record("Expected blob resource")
        }
    }

    @Test("ResourceContents without mimeType")
    func testResourceContentsWithoutMimeType() throws {
        let resource = ResourceContents.text(uri: "file://test.txt", mimeType: nil, text: "content")

        let encoded = try JSONEncoder().encode(resource)
        let decoded = try JSONDecoder().decode(ResourceContents.self, from: encoded)

        if case .text(let uri, let mimeType, let text) = decoded {
            #expect(uri == "file://test.txt")
            #expect(mimeType == nil)
            #expect(text == "content")
        } else {
            Issue.record("Expected text resource")
        }
    }

    // MARK: - CallToolResult Tests

    @Test("CallToolResult content variant encoding/decoding")
    func testCallToolResultContent() throws {
        let result = CallToolResult.content(
            content: [.text(ToolContent.TextContent(text: "Result"))],
            isError: false,
            meta: ["duration": .number(123)]
        )

        let encoded = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(CallToolResult.self, from: encoded)

        if case .content(let content, let isError, let meta) = decoded {
            #expect(content.count == 1)
            #expect(isError == false)
            #expect(meta?["duration"] == .number(123))
        } else {
            Issue.record("Expected content variant")
        }
    }

    @Test("CallToolResult with error flag")
    func testCallToolResultWithError() throws {
        let result = CallToolResult.content(
            content: [.text(ToolContent.TextContent(text: "Error message"))],
            isError: true,
            meta: nil
        )

        let encoded = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(CallToolResult.self, from: encoded)

        if case .content(_, let isError, let meta) = decoded {
            #expect(isError == true)
            #expect(meta == nil)
        } else {
            Issue.record("Expected content variant with error")
        }
    }

    @Test("CallToolResult isError default value")
    func testCallToolResultIsErrorDefault() throws {
        // Test that isError defaults to false when not present in JSON
        let json = """
        {
            "content": [{"type": "text", "text": "test"}]
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(CallToolResult.self, from: json)

        if case .content(_, let isError, _) = decoded {
            #expect(isError == false)
        } else {
            Issue.record("Expected content variant")
        }
    }

    @Test("CallToolResult isError not encoded when false")
    func testCallToolResultIsErrorNotEncodedWhenFalse() throws {
        let result = CallToolResult.content(
            content: [.text(ToolContent.TextContent(text: "test"))],
            isError: false,
            meta: nil
        )

        let encoded = try JSONEncoder().encode(result)
        let json = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]

        // isError should not be present when false (matches upstream behavior)
        #expect(json["isError"] == nil)
    }

    @Test("CallToolResult isError encoded when true")
    func testCallToolResultIsErrorEncodedWhenTrue() throws {
        let result = CallToolResult.content(
            content: [.text(ToolContent.TextContent(text: "error"))],
            isError: true,
            meta: nil
        )

        let encoded = try JSONEncoder().encode(result)
        let json = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]

        #expect(json["isError"] as? Bool == true)
    }

    @Test("CallToolResult toolResult variant encoding/decoding")
    func testCallToolResultToolResult() throws {
        let result = CallToolResult.toolResult(
            result: .object(["status": .string("success"), "value": .number(42)]),
            meta: nil
        )

        let encoded = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(CallToolResult.self, from: encoded)

        if case .toolResult(let toolResult, let meta) = decoded {
            if case .object(let obj) = toolResult {
                #expect(obj["status"] == .string("success"))
                #expect(obj["value"] == .number(42))
            } else {
                Issue.record("Expected object result")
            }
            #expect(meta == nil)
        } else {
            Issue.record("Expected toolResult variant")
        }
    }

    @Test("CallToolResult variant discrimination")
    func testCallToolResultVariantDiscrimination() throws {
        // Test that decoder correctly distinguishes between content and toolResult
        let contentJSON = """
        {
            "content": [{"type": "text", "text": "result"}]
        }
        """.data(using: .utf8)!

        let toolResultJSON = """
        {
            "toolResult": {"value": 42}
        }
        """.data(using: .utf8)!

        let contentDecoded = try JSONDecoder().decode(CallToolResult.self, from: contentJSON)
        let toolResultDecoded = try JSONDecoder().decode(CallToolResult.self, from: toolResultJSON)

        if case .content = contentDecoded {
            // Success
        } else {
            Issue.record("Expected content variant")
        }

        if case .toolResult = toolResultDecoded {
            // Success
        } else {
            Issue.record("Expected toolResult variant")
        }
    }

    // MARK: - PaginatedRequest Tests

    @Test("PaginatedRequest with cursor")
    func testPaginatedRequestWithCursor() throws {
        let request = PaginatedRequest(
            method: "tools/list",
            params: PaginatedRequest.PaginatedParams(cursor: "abc123", meta: ["page": .number(2)])
        )

        let encoded = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(PaginatedRequest.self, from: encoded)

        #expect(decoded.method == "tools/list")
        #expect(decoded.params?.cursor == "abc123")
        #expect(decoded.params?.meta?["page"] == .number(2))
    }

    @Test("PaginatedResult with nextCursor")
    func testPaginatedResultWithNextCursor() throws {
        let result = PaginatedResult(nextCursor: "next123", meta: nil)

        let encoded = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(PaginatedResult.self, from: encoded)

        #expect(decoded.nextCursor == "next123")
        #expect(decoded.meta == nil)
    }
}
