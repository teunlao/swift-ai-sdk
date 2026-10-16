import Foundation
import Testing
import SwiftAISDK
import AISDKProvider
import AISDKProviderUtils

@Suite("MCP HTTP contracts", .serialized)
struct MCPHTTPContractTests {
    @Test("Configured fetch handles initialization and streamed tool replies")
    func customFetch() async throws {
        let fetch: FetchFunction = { request in
            let url = try #require(request.url)
            #expect(request.fetchRedirectMode == .error)
            if request.httpMethod == "GET" {
                return FetchResponse(body: .none, urlResponse: try #require(HTTPURLResponse(url: url, statusCode: 405, httpVersion: nil, headerFields: nil)))
            }
            let message = try JSONDecoder().decode(JSONRPCMessage.self, from: #require(request.httpBody))
            guard case .request(let rpc) = message else {
                return FetchResponse(body: .none, urlResponse: try #require(HTTPURLResponse(url: url, statusCode: 202, httpVersion: nil, headerFields: nil)))
            }
            if rpc.method == "initialize" {
                let result = JSONRPCResponse(id: rpc.id, result: .object([
                    "protocolVersion": .string("2025-11-25"), "capabilities": .object(["tools": .object([:])]),
                    "serverInfo": .object(["name": .string("fetch-server"), "version": .string("1")]),
                ]))
                return FetchResponse(body: .data(try JSONEncoder().encode(result)), urlResponse: try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])))
            }
            #expect(rpc.method == "tools/call")
            #expect(rpc.params == .object(["name": .string("echo"), "arguments": .object([:])]))
            let result = JSONRPCResponse(id: rpc.id, result: .object(["content": .array([.object(["type": .string("text"), "text": .string("Streamed response")])])]))
            let frame = "data: " + String(decoding: try JSONEncoder().encode(result), as: UTF8.self) + "\n\n"
            return FetchResponse(body: .stream(AsyncThrowingStream { $0.yield(Data(frame.utf8)); $0.finish() }), urlResponse: try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])))
        }
        let client = try await createMCPClient(config: .init(transport: .config(.init(type: "http", url: "https://mcp.example.com/mcp", fetch: fetch))))
        #expect(client.serverInfo.name == "fetch-server")
        let result = try await client.callTool(name: "echo")
        guard case .content(let content, _, let isError, _) = result else { Issue.record("Expected streamed tool content"); try await client.close(); return }
        #expect(!isError)
        if case .text(let text) = content.first { #expect(text.text == "Streamed response") }
        else { Issue.record("Missing streamed text") }
        try await client.close()
    }

    @Test("HTTP transport failures expose status, endpoint and response body")
    func typedFailure() async throws {
        let end = TestURLProtocol.beginExclusiveAccess()
        defer { end() }
        TestURLProtocol.reset()
        TestURLProtocol.requestHandler = { request, _ in
            if request.httpMethod == "GET" { return .empty(status: 405) }
            return .data(status: 503, body: Data("Service unavailable".utf8))
        }
        let url = "https://mcp.example.com/mcp"
        let transport = try HttpMCPTransport(config: .init(type: "http", url: url), session: makeTestSession())
        try await transport.start()
        do {
            try await transport.send(message: .request(.init(id: .int(1), method: "tools/list")))
            Issue.record("HTTP 503 returned without a typed failure")
        } catch let error as MCPClientError {
            #expect(error.statusCode == 503)
            #expect(error.url == url)
            #expect(error.responseBody == "Service unavailable")
            #expect(error.code == nil)
        }
        try await transport.close()
    }

    @Test("JSON-RPC errors from unsuccessful HTTP responses retain application codes")
    func applicationError() async throws {
        let end = TestURLProtocol.beginExclusiveAccess()
        defer { end() }
        TestURLProtocol.reset()
        TestURLProtocol.requestHandler = { request, _ in
            if request.httpMethod == "GET" { return .empty(status: 405) }
            return .jsonValue(status: 400, body: .object([
                "jsonrpc": .string("2.0"),
                "error": .object(["code": .number(-32602), "message": .string("Invalid arguments"), "data": .object(["field": .string("name")])]),
            ]))
        }
        let transport = try HttpMCPTransport(config: .init(type: "http", url: "https://mcp.example.com/mcp"), session: makeTestSession())
        let client = try await createMCPClient(config: .init(
            transport: .custom(transport),
            initialInitializeResult: .init(protocolVersion: "2025-11-25", capabilities: .init(tools: .init()), serverInfo: .init(name: "server", version: "1")),
            maxRetries: 1
        ))
        do {
            _ = try await client.callTool(name: "search")
            Issue.record("JSON-RPC error returned a successful tool result")
        } catch let error as MCPClientError {
            #expect(error.code == -32602)
            #expect(error.statusCode == nil)
            #expect((error.data as? JSONValue) == .object(["field": .string("name")]))
            #expect(error.cause is JSONRPCErrorObject)
        }
        try await client.close()
    }

    @Test("Initialization omits stale sessions and subsequent requests use the negotiated version")
    func negotiatedHeaders() async throws {
        let end = TestURLProtocol.beginExclusiveAccess()
        defer { end() }
        TestURLProtocol.reset()
        TestURLProtocol.requestHandler = { request, _ in
            guard request.httpMethod == "POST" else { return .empty(status: 405) }
            let data = try #require(request.httpBody ?? TestURLProtocol.takeCalls().last?.requestBody)
            let message = try JSONDecoder().decode(JSONRPCMessage.self, from: data)
            if case .request(let rpc) = message {
                #expect(rpc.method == "initialize")
                if case .object(let params) = rpc.params { #expect(params["protocolVersion"] == .string("2025-11-25")) }
                else { Issue.record("Initialize request is missing protocol parameters") }
                #expect(request.value(forHTTPHeaderField: "mcp-session-id") == nil)
                #expect(request.value(forHTTPHeaderField: "mcp-protocol-version") == "2025-11-25")
                return .jsonValue(headers: ["Content-Type": "application/json", "mcp-session-id": "new-session"], body: .object([
                    "jsonrpc": .string("2.0"), "id": .number(0), "result": .object([
                        "protocolVersion": .string("2024-11-05"), "capabilities": .object([:]),
                        "serverInfo": .object(["name": .string("legacy"), "version": .string("1")]),
                    ]),
                ]))
            }
            #expect(request.value(forHTTPHeaderField: "mcp-protocol-version") == "2024-11-05")
            #expect(request.value(forHTTPHeaderField: "mcp-session-id") == "new-session")
            return .empty(status: 202)
        }
        let transport = try HttpMCPTransport(config: .init(type: "http", url: "https://mcp.example.com/mcp", initialSessionId: "stale", initialProtocolVersion: "2024-11-05", terminateSessionOnClose: false), session: makeTestSession())
        let client = try await createMCPClient(config: .init(transport: .custom(transport)))
        #expect(client.initializeResult.protocolVersion == "2024-11-05")
        try await client.close()
    }
}
