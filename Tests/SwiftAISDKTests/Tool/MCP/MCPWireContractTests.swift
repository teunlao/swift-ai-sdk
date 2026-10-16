import Testing
import SwiftAISDK
import AISDKProvider

@Suite("MCP wire contracts")
struct MCPWireContractTests {
    @Test("JSON-RPC rejects ambiguous messages and accepts errors without an ID")
    func rpcValidation() throws {
        #expect(throws: (any Error).self) {
            try validateJSONRPCMessage(.object([
                "jsonrpc": .string("2.0"), "id": .number(1), "method": .string("tools/list"), "result": .object([:]),
            ]))
        }
        #expect(throws: (any Error).self) {
            try validateJSONRPCMessage(.object([
                "jsonrpc": .string("2.0"), "method": .string("tools/list"), "params": .array([]),
            ]))
        }
        let message = try validateJSONRPCMessage(.object([
            "jsonrpc": .string("2.0"), "error": .object(["code": .number(-32600), "message": .string("Invalid request")]),
        ]))
        guard case .error(let error) = message else { Issue.record("Expected a JSON-RPC error"); return }
        #expect(error.id == nil)
        #expect(error.error.code == -32600)
    }

    @Test("Structured-only tool results synthesize text while preserving extension fields")
    func structuredOnlyResult() async throws {
        let client = try await createMCPClient(config: .init(transport: .custom(MockMCPTransport(toolCallResults: [
            "mock-tool": .raw(.object(["structuredContent": .object(["url": .string("https://example.com")]), "toolResult": .string("legacy"), "extension": .string("kept")])),
        ]))))
        let tools = try await client.tools()
        let result = try await #require(tools["mock-tool"]).execute(input: .object([:])).resolve()
        #expect(result == .object([
            "content": .array([.object(["type": .string("text"), "text": .string("{\"url\":\"https://example.com\"}")])]),
            "structuredContent": .object(["url": .string("https://example.com")]), "toolResult": .string("legacy"), "isError": .bool(false), "extension": .string("kept"),
        ]))
        try await client.close()
    }

    @Test("Legacy tool results remain valid when a content-shaped extension is present")
    func legacyResultFallback() async throws {
        let payload: JSONValue = .object(["toolResult": .object(["value": .number(42)]), "content": .string("legacy text")])
        let client = try await createMCPClient(config: .init(transport: .custom(MockMCPTransport(toolCallResults: ["mock-tool": .raw(payload)]))))
        let tools = try await client.tools()
        let result = try await #require(tools["mock-tool"]).execute(input: .object([:])).resolve()
        #expect(result == payload)
        try await client.close()
    }

    @Test("Embedded resources retain server extension fields in tool output")
    func resourceExtensions() async throws {
        let content: JSONValue = .object([
            "type": .string("resource"), "resource": .object([
                "uri": .string("file:///result.txt"), "text": .string("Result"),
                "_meta": .object(["vendor": .string("metadata")]),
                "annotations": .object(["audience": .array([.string("user")])]),
            ]),
        ])
        let client = try await createMCPClient(config: .init(transport: .custom(MockMCPTransport(toolCallResults: ["mock-tool": .raw(.object(["content": .array([content])]))]))))
        let tools = try await client.tools()
        let result = try await #require(tools["mock-tool"]).execute(input: .object([:])).resolve()
        #expect(result == .object(["content": .array([content]), "isError": .bool(false)]))
        try await client.close()
    }

    @Test("Malformed known content types fail at the client response boundary")
    func malformedImage() async throws {
        let client = try await createMCPClient(config: .init(transport: .custom(MockMCPTransport(toolCallResults: [
            "mock-tool": .raw(.object(["content": .array([.object(["type": .string("image"), "data": .string("not-base64!"), "mimeType": .string("image/png")])])])),
        ]))))
        await #expect(throws: MCPClientError.self) { try await client.callTool(name: "mock-tool") }
        try await client.close()
    }
}
