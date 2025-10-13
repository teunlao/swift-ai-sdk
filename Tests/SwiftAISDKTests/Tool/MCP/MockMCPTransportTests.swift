/**
 Tests for MockMCPTransport.

 Port of mock transport usage patterns from `@ai-sdk/ai/src/tool/mcp/mock-mcp-transport.ts`.

 These tests verify the mock transport works correctly for testing MCP clients.
 */

import Testing
import Foundation
@testable import SwiftAISDK
@testable import AISDKProvider

// Helper to allow mutation in concurrent closures
final class MessageBox: @unchecked Sendable {
    var value: JSONRPCMessage?
    private let lock = NSLock()

    init() {
        self.value = nil
    }

    func set(_ newValue: JSONRPCMessage?) {
        lock.lock()
        defer { lock.unlock() }
        value = newValue
    }

    func get() -> JSONRPCMessage? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

final class ErrorBox: @unchecked Sendable {
    var value: Error?
    private let lock = NSLock()

    init() {
        self.value = nil
    }

    func set(_ newValue: Error?) {
        lock.lock()
        defer { lock.unlock() }
        value = newValue
    }

    func get() -> Error? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

final class BoolBox: @unchecked Sendable {
    var value: Bool
    private let lock = NSLock()

    init(_ initialValue: Bool) {
        self.value = initialValue
    }

    func set(_ newValue: Bool) {
        lock.lock()
        defer { lock.unlock() }
        value = newValue
    }

    func get() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

@Suite("MockMCPTransport")
struct MockMCPTransportTests {

    // MARK: - Initialization Tests

    @Test("MockMCPTransport handles initialize request")
    func testInitializeRequest() async throws {
        let transport = MockMCPTransport()

        let messageBox = MessageBox()
        transport.onmessage = { message in
            messageBox.set(message)
        }

        try await transport.start()

        let request = JSONRPCRequest(
            id: .string("1"),
            method: "initialize",
            params: BaseParams()
        )

        try await transport.send(message: .request(request))

        // Wait a bit for async response
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms

        let receivedMessage = messageBox.get()
        #expect(receivedMessage != nil)
        if case .response(let response) = receivedMessage {
            if case .object(let result) = response.result {
                // Check protocol version
                if case .string(let version) = result["protocolVersion"] {
                    #expect(version == "2025-06-18")
                }
                // Check server info
                if case .object(let serverInfo) = result["serverInfo"],
                   case .string(let name) = serverInfo["name"] {
                    #expect(name == "mock-mcp-server")
                }
            } else {
                Issue.record("Expected object result")
            }
        } else {
            Issue.record("Expected response message")
        }
    }

    @Test("MockMCPTransport handles tools/list request")
    func testToolsListRequest() async throws {
        let transport = MockMCPTransport()

        let messageBox = MessageBox()
        transport.onmessage = { message in
            messageBox.set(message)
        }

        try await transport.start()

        let request = JSONRPCRequest(
            id: .string("2"),
            method: "tools/list",
            params: BaseParams()
        )

        try await transport.send(message: .request(request))

        // Wait for async response
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms

        let receivedMessage = messageBox.get()
        #expect(receivedMessage != nil)
        if case .response(let response) = receivedMessage {
            if case .object(let result) = response.result,
               case .array(let tools) = result["tools"] {
                #expect(tools.count == 2) // Default has 2 mock tools
            } else {
                Issue.record("Expected tools array in result")
            }
        } else {
            Issue.record("Expected response message")
        }
    }

    @Test("MockMCPTransport returns error when tools list is empty")
    func testEmptyToolsList() async throws {
        let transport = MockMCPTransport(overrideTools: [])

        let messageBox = MessageBox()
        transport.onmessage = { message in
            messageBox.set(message)
        }

        try await transport.start()

        let request = JSONRPCRequest(
            id: .string("3"),
            method: "tools/list",
            params: BaseParams()
        )

        try await transport.send(message: .request(request))

        // Wait for async response
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms

        let receivedMessage = messageBox.get()
        #expect(receivedMessage != nil)
        if case .error(let error) = receivedMessage {
            #expect(error.error.code == -32000)
            #expect(error.error.message == "Method not supported")
        } else {
            Issue.record("Expected error message for empty tools list")
        }
    }

    @Test("MockMCPTransport handles custom initialize result")
    func testCustomInitializeResult() async throws {
        let customResult: JSONValue = .object([
            "protocolVersion": .string("custom-version"),
            "serverInfo": .object([
                "name": .string("custom-server"),
                "version": .string("2.0.0")
            ]),
            "capabilities": .object([:])
        ])

        let transport = MockMCPTransport(initializeResult: customResult)

        let messageBox = MessageBox()
        transport.onmessage = { message in
            messageBox.set(message)
        }

        try await transport.start()

        let request = JSONRPCRequest(
            id: .string("4"),
            method: "initialize",
            params: BaseParams()
        )

        try await transport.send(message: .request(request))

        // Wait for async response
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms

        let receivedMessage = messageBox.get()
        #expect(receivedMessage != nil)
        if case .response(let response) = receivedMessage {
            if case .object(let result) = response.result,
               case .string(let version) = result["protocolVersion"] {
                #expect(version == "custom-version")
            } else {
                Issue.record("Expected custom protocol version")
            }
        } else {
            Issue.record("Expected response message")
        }
    }

    @Test("MockMCPTransport calls onerror when sendError is true")
    func testSendErrorCallback() async throws {
        let transport = MockMCPTransport(sendError: true)

        let errorBox = ErrorBox()
        transport.onerror = { error in
            errorBox.set(error)
        }

        try await transport.start()

        // Wait a bit for error callback
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms

        #expect(errorBox.get() != nil)
    }

    @Test("MockMCPTransport calls onclose")
    func testOncloseCallback() async throws {
        let transport = MockMCPTransport()

        let closeBox = BoolBox(false)
        transport.onclose = {
            closeBox.set(true)
        }

        try await transport.start()
        try await transport.close()

        #expect(closeBox.get() == true)
    }

    @Test("MockMCPTransport with custom tools")
    func testCustomTools() async throws {
        let customTools = [
            MCPTool(
                name: "custom-tool",
                description: "A custom test tool",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "param": .object(["type": .string("string")])
                    ])
                ])
            )
        ]

        let transport = MockMCPTransport(overrideTools: customTools)

        let messageBox = MessageBox()
        transport.onmessage = { message in
            messageBox.set(message)
        }

        try await transport.start()

        let request = JSONRPCRequest(
            id: .string("5"),
            method: "tools/list",
            params: BaseParams()
        )

        try await transport.send(message: .request(request))

        // Wait for async response
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms

        let receivedMessage = messageBox.get()
        #expect(receivedMessage != nil)
        if case .response(let response) = receivedMessage {
            if case .object(let result) = response.result,
               case .array(let tools) = result["tools"] {
                #expect(tools.count == 1)
                if case .object(let tool) = tools[0],
                   case .string(let name) = tool["name"] {
                    #expect(name == "custom-tool")
                }
            } else {
                Issue.record("Expected tools array with custom tool")
            }
        } else {
            Issue.record("Expected response message")
        }
    }
}
