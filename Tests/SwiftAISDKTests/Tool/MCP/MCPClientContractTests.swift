import Foundation
import Testing
import SwiftAISDK
import AISDKProvider
import AISDKProviderUtils

private final class ContractTransport: MCPTransport, @unchecked Sendable {
    let respond: @Sendable (JSONRPCRequest) async throws -> JSONValue?
    let begin: @Sendable () async throws -> Void
    var onclose: (@Sendable () -> Void)?
    var onerror: (@Sendable (Error) -> Void)?
    var onmessage: (@Sendable (JSONRPCMessage) -> Void)?
    let requestSignal = TestURLProtocol.LockedValue<(@Sendable () -> Bool)?>(nil)

    init(respond: @escaping @Sendable (JSONRPCRequest) async throws -> JSONValue?) {
        self.begin = {}
        self.respond = respond
    }

    init(begin: @escaping @Sendable () async throws -> Void) {
        self.begin = begin
        self.respond = { _ in nil }
    }

    func start() async throws { try await begin() }
    func close() async throws { onclose?() }
    func send(message: JSONRPCMessage, options: MCPTransportSendOptions?) async throws {
        requestSignal.set(options?.signal)
        try await send(message: message)
    }

    func send(message: JSONRPCMessage) async throws {
        if case .request(let request) = message, let result = try await respond(request) {
            onmessage?(.response(.init(id: request.id, result: result)))
        }
    }
}

@Suite("MCPClient contracts")
struct MCPClientContractTests {
    private var initializeResult: InitializeResult {
        .init(protocolVersion: "2025-11-25", capabilities: .init(completions: [:], tools: .init()),
              serverInfo: .init(name: "test-server", version: "1", title: "Server"), instructions: "Server instructions")
    }

    @Test("Cached initialization preserves server information and skips a second handshake")
    func cachedInitialization() async throws {
        let transport = ContractTransport { request in
            throw MCPClientError(message: "Unexpected handshake: \(request.method)")
        }
        let client = try await createMCPClient(config: .init(transport: .custom(transport), initialInitializeResult: initializeResult))
        #expect(client.initializeResult.protocolVersion == "2025-11-25")
        #expect(client.serverInfo.title == "Server")
        #expect(client.instructions == "Server instructions")
        try await client.close()
    }

    @Test("Tool discovery follows pagination and publishes behavioral annotations")
    func paginatedTools() async throws {
        let transport = ContractTransport { request in
            guard request.method == "tools/list" else { return nil }
            if request.params == .object(["cursor": .string("page-2")]) {
                return .object(["tools": .array([.object([
                    "name": .string("second"), "inputSchema": .object([:]),
                    "annotations": .object(["title": .string("Second"), "readOnlyHint": .bool(true), "destructiveHint": .bool(false)]),
                ])])])
            }
            return .object(["tools": .array([.object(["name": .string("first"), "inputSchema": .object([:])])]), "nextCursor": .string("page-2")])
        }
        let client = try await createMCPClient(config: .init(transport: .custom(transport), clientName: "host", initialInitializeResult: initializeResult))
        let tools = try await client.tools()
        #expect(Set(tools.keys) == ["first", "second"])
        let expectedMetadata: [String: JSONValue] = [
            "clientName": .string("host"), "toolName": .string("second"), "title": .string("Second"),
            "annotations": .object(["title": .string("Second"), "readOnlyHint": .bool(true), "destructiveHint": .bool(false)]),
        ]
        #expect(tools["second"]?.metadata == expectedMetadata)
        try await client.close()
    }

    @Test("Failed tool results bypass structured output validation and need no execution options")
    func errorResultBypassesSchema() async throws {
        let client = try await createMCPClient(config: .init(transport: .custom(MockMCPTransport(
            toolCallResults: ["mock-tool": .content(content: [.text(.init(text: "Permission denied"))], structuredContent: nil, isError: true, meta: nil)]
        ))))
        let tools = try await client.tools(options: .init(schemas: .schemas([
            "mock-tool": .init(inputSchema: FlexibleSchema(jsonSchema(.object([:]))), outputSchema: FlexibleSchema(jsonSchema(.object(["type": .string("number")])))),
        ])))
        let result = try await #require(tools["mock-tool"]).execute(input: .object([:])).resolve()
        #expect(result == .object(["content": .array([.object(["type": .string("text"), "text": .string("Permission denied")])]), "isError": .bool(true)]))
        try await client.close()
    }

    @Test("Tool calls retry transient HTTP failures from custom transports")
    func transientTransportFailure() async throws {
        let first = BoolBox(true)
        let transport = ContractTransport { _ in
            if first.get() {
                first.set(false)
                throw APICallError(message: "Temporarily unavailable", url: "https://mcp.example.com", requestBodyValues: nil, statusCode: 503, isRetryable: false)
            }
            return .object(["content": .array([.object(["type": .string("text"), "text": .string("Recovered")])])])
        }
        let client = try await createMCPClient(config: .init(transport: .custom(transport), initialInitializeResult: initializeResult, maxRetries: 1))
        let result = try await client.callTool(name: "echo")
        guard case .content(let content, _, let isError, _) = result else { Issue.record("Expected a recovered tool result"); try await client.close(); return }
        #expect(!isError)
        if case .text(let text) = content.first { #expect(text.text == "Recovered") }
        else { Issue.record("Missing recovered text") }
        try await client.close()
    }

    @Test("Discovered tools retain the connection needed for execution")
    func toolsRetainClient() async throws {
        func discover() async throws -> [String: Tool] {
            let client = try await createMCPClient(config: .init(transport: .custom(MockMCPTransport())))
            return try await client.tools()
        }
        let tools = try await discover()
        let result = try await #require(tools["mock-tool"]).execute(input: .object([:])).resolve()
        #expect(result == .object([
            "content": .array([.object(["type": .string("text"), "text": .string("Mock tool call result")])]),
            "isError": .bool(false),
        ]))
    }

    @Test("A successful reply leaves the transport request signal live")
    func successfulRequestSignal() async throws {
        let transport = ContractTransport { _ in .object(["content": .array([])]) }
        let client = try await createMCPClient(config: .init(transport: .custom(transport), initialInitializeResult: initializeResult))
        let signal = BoolBox(false)
        let result = try await client.callTool(name: "echo", arguments: nil, options: .init(signal: { signal.get() }))
        #expect(!result.isError)
        #expect(transport.requestSignal.get()?() == false)
        signal.set(true)
        #expect(transport.requestSignal.get()?() == true)
        try await client.close()
    }

    @Test("Request deadlines remove handlers before late responses arrive")
    func deadlineCleanup() async throws {
        let requestPromise = createResolvablePromise(of: JSONRPCRequest.self)
        let errors = ErrorBox()
        let transport = ContractTransport { request in requestPromise.resolve(request); return nil }
        let client = try await createMCPClient(config: .init(transport: .custom(transport), onUncaughtError: { errors.set($0) }, initialInitializeResult: initializeResult))
        await #expect(throws: MCPClientError.self) {
            try await client.listTools(options: .init(options: .init(timeout: 1, maxTotalTimeout: 0.02)))
        }
        let request = try await requestPromise.task.value
        transport.onmessage?(.response(.init(id: request.id, result: .object(["tools": .array([])]))))
        #expect((errors.get() as? MCPClientError)?.message.hasPrefix("Protocol error:") == true)
        try await client.close()
    }

    @Test("Task and signal cancellation remove in-flight response handlers", arguments: [false, true])
    func cancellationCleanup(useSignal: Bool) async throws {
        let requestPromise = createResolvablePromise(of: JSONRPCRequest.self)
        let errors = ErrorBox()
        let transport = ContractTransport { request in requestPromise.resolve(request); return nil }
        let client = try await createMCPClient(config: .init(transport: .custom(transport), onUncaughtError: { errors.set($0) }, initialInitializeResult: initializeResult))
        let signal = BoolBox(false)
        let task = Task { try await client.listTools(options: .init(options: .init(signal: { signal.get() }))) }
        let request = try await requestPromise.task.value
        if useSignal { signal.set(true) } else { task.cancel() }
        do { _ = try await task.value; Issue.record("Cancelled request returned a result") }
        catch let error as MCPClientError {
            #expect(error.message == "Request was aborted")
            if !useSignal { #expect(error.cause is CancellationError) }
        }
        transport.onmessage?(.response(.init(id: request.id, result: .object(["tools": .array([])]))))
        #expect((errors.get() as? MCPClientError)?.message.hasPrefix("Protocol error:") == true)
        try await client.close()
    }

    @Test("Initialization deadline includes transport startup")
    func startupDeadline() async throws {
        let transport = ContractTransport(begin: { try await Task.sleep(nanoseconds: 10_000_000_000) })
        do {
            _ = try await createMCPClient(config: .init(transport: .custom(transport), initializationOptions: .init(timeout: 0.02)))
            Issue.record("Initialization returned despite a startup deadline")
        } catch let error as MCPClientError {
            #expect(error.message == "MCP client initialization timed out after 20ms")
        }
    }

    @Test("Completion preserves prompt references and prior argument context")
    func completions() async throws {
        let transport = ContractTransport { request in
            #expect(request.method == "completion/complete")
            #expect(request.params == .object([
                "ref": .object(["type": .string("ref/prompt"), "name": .string("review")]),
                "argument": .object(["name": .string("language"), "value": .string("sw")]),
                "context": .object(["arguments": .object(["framework": .string("SwiftUI")])]),
            ]))
            return .object(["completion": .object(["values": .array([.string("swift")]), "total": .number(1), "hasMore": .bool(false)])])
        }
        let client = try await createMCPClient(config: .init(transport: .custom(transport), initialInitializeResult: initializeResult))
        let result = try await client.complete(args: .init(ref: .prompt(name: "review"), argument: .init(name: "language", value: "sw"), context: .init(arguments: ["framework": "SwiftUI"])))
        #expect(result.completion.values == ["swift"])
        #expect(result.completion.total == 1)
        try await client.close()
    }
}
