/**
 Tests for MCP Transport layer.

 Port of `@ai-sdk/ai/src/tool/mcp/mcp-sse-transport.test.ts`.

 Note: Full SSE integration tests (with HTTP server mocking) are simplified here
 due to lack of test server infrastructure. The tests focus on:
 - MockMCPTransport functionality
 - Message deserialization
 - Transport protocol interface
 - Basic error handling

 Full HTTP/SSE integration testing would require a test server implementation
 similar to `@ai-sdk/test-server`.
 */

import Foundation
import Testing

@testable import SwiftAISDK

@Suite("MCPTransport")
struct MCPTransportTests {

    // MARK: - Factory Function Tests

    @Test("createMcpTransport creates SSE transport")
    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    func testCreateSseTransport() throws {
        let config = MCPTransportConfig(
            type: "sse",
            url: "http://localhost:3000/sse"
        )

        let transport = try createMcpTransport(config: config)
        #expect(transport is SseMCPTransport)
    }

    @Test("createMcpTransport throws for unsupported transport type")
    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    func testCreateUnsupportedTransport() {
        let config = MCPTransportConfig(
            type: "websocket",
            url: "ws://localhost:3000"
        )

        #expect(throws: MCPClientError.self) {
            try createMcpTransport(config: config)
        }
    }

    @Test("isCustomMcpTransport identifies transport instances")
    func testIsCustomMcpTransport() {
        let transport = MockMCPTransport()
        #expect(isCustomMcpTransport(transport))

        let config = MCPTransportConfig(url: "http://test.com")
        #expect(!isCustomMcpTransport(config))
    }

    // MARK: - Message Deserialization Tests

    @Test("deserializeMessage parses valid JSON-RPC request")
    func testDeserializeRequest() throws {
        let json = """
            {"jsonrpc":"2.0","id":"1","method":"test","params":{}}
            """

        let message = try deserializeMessage(json)

        if case .request(let request) = message {
            #expect(request.method == "test")
            switch request.id {
            case .string(let id):
                #expect(id == "1")
            case .int:
                Issue.record("Expected string ID")
            }
        } else {
            Issue.record("Expected request message")
        }
    }

    @Test("deserializeMessage parses valid JSON-RPC response")
    func testDeserializeResponse() throws {
        let json = """
            {"jsonrpc":"2.0","id":"1","result":{"ok":true}}
            """

        let message = try deserializeMessage(json)

        if case .response(let response) = message {
            switch response.id {
            case .string(let id):
                #expect(id == "1")
            case .int:
                Issue.record("Expected string ID")
            }
            if case .object(let obj) = response.result,
                case .bool(let ok) = obj["ok"]
            {
                #expect(ok == true)
            } else {
                Issue.record("Expected object result with ok=true")
            }
        } else {
            Issue.record("Expected response message")
        }
    }

    @Test("deserializeMessage parses valid JSON-RPC error")
    func testDeserializeError() throws {
        let json = """
            {"jsonrpc":"2.0","id":"1","error":{"code":-32601,"message":"Method not found"}}
            """

        let message = try deserializeMessage(json)

        if case .error(let error) = message {
            #expect(error.error.code == -32601)
            #expect(error.error.message == "Method not found")
        } else {
            Issue.record("Expected error message")
        }
    }

    @Test("deserializeMessage parses notification")
    func testDeserializeNotification() throws {
        let json = """
            {"jsonrpc":"2.0","method":"notify","params":{}}
            """

        let message = try deserializeMessage(json)

        if case .notification(let notification) = message {
            #expect(notification.method == "notify")
        } else {
            Issue.record("Expected notification message")
        }
    }

    @Test("deserializeMessage throws on invalid JSON")
    func testDeserializeInvalidJSON() {
        let invalidJson = "not a json"

        #expect(throws: Error.self) {
            try deserializeMessage(invalidJson)
        }
    }
}
