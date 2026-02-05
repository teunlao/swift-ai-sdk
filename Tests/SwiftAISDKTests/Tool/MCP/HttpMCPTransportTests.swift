/**
 Tests for HttpMCPTransport.
 
 Port of `packages/mcp/src/tool/mcp-http-transport.test.ts`.
 */

import Foundation
import Testing

@testable import SwiftAISDK
@testable import AISDKProvider

@Suite("HttpMCPTransport", .serialized)
struct HttpMCPTransportTests {

    // MARK: - Helpers

    private func eventually(
        timeout: TimeInterval = 1.0,
        intervalNanoseconds: UInt64 = 10_000_000,
        _ predicate: @escaping @Sendable () -> Bool
    ) async -> Bool {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if predicate() { return true }
            try? await Task.sleep(nanoseconds: intervalNanoseconds)
        }
        return predicate()
    }

    @Test("should POST JSON and receive JSON response")
    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    func postJSONAndReceiveJSONResponse() async throws {
        let endExclusive = TestURLProtocol.beginExclusiveAccess()
        defer { endExclusive() }
        TestURLProtocol.reset()
        let session = makeTestSession()

        let mcpUrl = "http://localhost:4000/mcp"

        TestURLProtocol.requestHandler = { request, _ in
            let url = normalizeTestURL(try #require(request.url?.absoluteString))
            switch (request.httpMethod ?? "GET", url) {
            case ("GET", mcpUrl):
                // no inbound SSE available in this test
                return .empty(status: 405)
            case ("POST", mcpUrl):
                return .jsonValue(
                    status: 200,
                    headers: [
                        "content-type": "application/json",
                        "mcp-session-id": "abc123",
                    ],
                    body: .object([
                        "jsonrpc": .string("2.0"),
                        "id": .number(1),
                        "result": .object(["ok": .bool(true)]),
                    ])
                )
            default:
                return .empty(status: 404)
            }
        }

        let transport = try HttpMCPTransport(config: MCPTransportConfig(type: "http", url: mcpUrl), session: session)

        do {
            try await transport.start()

            let msgPromise = createResolvablePromise(of: JSONRPCMessage.self)
            transport.onmessage = { msg in
                msgPromise.resolve(msg)
            }

            let message = JSONRPCMessage.request(
                JSONRPCRequest(id: .int(1), method: "initialize", params: .object([:]))
            )

            try await transport.send(message: message)

            let received = try await msgPromise.task.value
            guard case .response(let response) = received else {
                Issue.record("Expected response message")
                try? await transport.close()
                return
            }

            #expect(response.id == .int(1))
            #expect(response.result == .object(["ok": .bool(true)]))

            let calls = TestURLProtocol.takeCalls()
            let post = try #require(
                calls.first(where: { $0.requestMethod == "POST" && normalizeTestURL($0.requestUrl) == mcpUrl })
            )
            #expect(post.requestHeaders["mcp-protocol-version"] == LATEST_PROTOCOL_VERSION)
            #expect(post.requestHeaders["accept"] == "application/json, text/event-stream")
            #expect(post.requestHeaders["content-type"] == "application/json")
        } catch {
            try? await transport.close()
            throw error
        }

        try await transport.close()
    }

    @Test("should handle text/event-stream responses")
    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    func handleTextEventStreamResponses() async throws {
        let endExclusive = TestURLProtocol.beginExclusiveAccess()
        defer { endExclusive() }
        TestURLProtocol.reset()
        let session = makeTestSession()

        let streamUrl = "http://localhost:4000/stream"
        let controller = TestURLProtocol.makeController()

        TestURLProtocol.requestHandler = { request, _ in
            let url = normalizeTestURL(try #require(request.url?.absoluteString))
            switch (request.httpMethod ?? "GET", url) {
            case ("GET", streamUrl):
                return .empty(status: 405)
            case ("POST", streamUrl):
                return .stream(
                    status: 200,
                    headers: ["content-type": "text/event-stream"],
                    controller: controller
                )
            default:
                return .empty(status: 404)
            }
        }

        let transport = try HttpMCPTransport(config: MCPTransportConfig(type: "http", url: streamUrl), session: session)
        do {
            try await transport.start()

            let msgPromise = createResolvablePromise(of: JSONRPCMessage.self)
            transport.onmessage = { msg in
                msgPromise.resolve(msg)
            }

            let message = JSONRPCMessage.request(
                JSONRPCRequest(id: .int(2), method: "initialize", params: .object([:]))
            )

            try await transport.send(message: message)

            controller.write(
                "event: message\ndata: {\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"ok\":true}}\n\n"
            )
            controller.finish()

            let received = try await msgPromise.task.value
            guard case .response(let response) = received else {
                Issue.record("Expected response message")
                try? await transport.close()
                return
            }

            #expect(response.id == .int(2))
            #expect(response.result == .object(["ok": .bool(true)]))
        } catch {
            try? await transport.close()
            throw error
        }

        try await transport.close()
    }

    @Test("should (re)open inbound SSE after 202 Accepted")
    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    func reopenInboundSSEAfter202() async throws {
        let endExclusive = TestURLProtocol.beginExclusiveAccess()
        defer { endExclusive() }
        TestURLProtocol.reset()
        let session = makeTestSession()

        let mcpUrl = "http://localhost:4000/mcp"
        let controller = TestURLProtocol.makeController()
        let postReturned202 = TestURLProtocol.LockedValue(false)

        TestURLProtocol.requestHandler = { request, _ in
            let url = normalizeTestURL(try #require(request.url?.absoluteString))
            let method = request.httpMethod ?? "GET"

            guard url == mcpUrl else { return .empty(status: 404) }

            if method == "POST" {
                postReturned202.set(true)
                return .empty(status: 202)
            }

            // GET
            let alreadyAccepted = postReturned202.get()
            if alreadyAccepted {
                return .stream(
                    status: 200,
                    headers: ["content-type": "text/event-stream"],
                    controller: controller
                )
            } else {
                return .empty(status: 405)
            }
        }

        let transport = try HttpMCPTransport(config: MCPTransportConfig(type: "http", url: mcpUrl), session: session)
        do {
            try await transport.start()

            try await transport.send(
                message: .request(JSONRPCRequest(id: .int(1), method: "initialize", params: .object([:])))
            )

            let didOpenSecondGet = await eventually {
                let calls = TestURLProtocol.takeCalls()
                let getCount = calls.filter { $0.requestMethod == "GET" && normalizeTestURL($0.requestUrl) == mcpUrl }.count
                return getCount >= 2
            }

            #expect(didOpenSecondGet == true)

            controller.finish()
        } catch {
            controller.finish()
            try? await transport.close()
            throw error
        }

        try await transport.close()
    }

    @Test("should DELETE to terminate session on close when session exists")
    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    func deleteOnCloseWhenSessionExists() async throws {
        let endExclusive = TestURLProtocol.beginExclusiveAccess()
        defer { endExclusive() }
        TestURLProtocol.reset()
        let session = makeTestSession()

        let mcpUrl = "http://localhost:4000/mcp"

        TestURLProtocol.requestHandler = { request, _ in
            let url = normalizeTestURL(try #require(request.url?.absoluteString))
            let method = request.httpMethod ?? "GET"

            guard url == mcpUrl else { return .empty(status: 404) }

            switch method {
            case "GET":
                return .empty(status: 405)
            case "POST":
                return .jsonValue(
                    status: 200,
                    headers: [
                        "content-type": "application/json",
                        "mcp-session-id": "xyz-session",
                    ],
                    body: .object([
                        "jsonrpc": .string("2.0"),
                        "id": .number(1),
                        "result": .object(["ok": .bool(true)]),
                    ])
                )
            case "DELETE":
                return .empty(status: 200)
            default:
                return .empty(status: 404)
            }
        }

        let transport = try HttpMCPTransport(config: MCPTransportConfig(type: "http", url: mcpUrl), session: session)

        try await transport.start()
        try await transport.send(
            message: .request(JSONRPCRequest(id: .int(1), method: "initialize", params: .object([:])))
        )
        try await transport.close()

        let calls = TestURLProtocol.takeCalls()
        let delete = try #require(
            calls.first(where: { $0.requestMethod == "DELETE" && normalizeTestURL($0.requestUrl) == mcpUrl })
        )
        #expect(delete.requestHeaders["mcp-session-id"] == "xyz-session")
    }

    @Test("should report HTTP errors from POST")
    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    func reportHttpErrorsFromPOST() async throws {
        let endExclusive = TestURLProtocol.beginExclusiveAccess()
        defer { endExclusive() }
        TestURLProtocol.reset()
        let session = makeTestSession()

        let mcpUrl = "http://localhost:4000/mcp"
        let controller = TestURLProtocol.makeController()

        TestURLProtocol.requestHandler = { request, _ in
            let url = normalizeTestURL(try #require(request.url?.absoluteString))
            let method = request.httpMethod ?? "GET"
            guard url == mcpUrl else { return .empty(status: 404) }

            if method == "GET" {
                return .stream(
                    status: 200,
                    headers: ["content-type": "text/event-stream"],
                    controller: controller
                )
            }

            if method == "POST" {
                return .data(
                    status: 500,
                    headers: ["content-type": "text/plain"],
                    body: Data("Internal Server Error".utf8)
                )
            }

            return .empty(status: 404)
        }

        let transport = try HttpMCPTransport(config: MCPTransportConfig(type: "http", url: mcpUrl), session: session)
        do {
            let errorPromise = createResolvablePromise(of: Error.self)
            transport.onerror = { error in
                errorPromise.resolve(error)
            }

            try await transport.start()

            await #expect(throws: Error.self) {
                try await transport.send(
                    message: .request(JSONRPCRequest(id: .int(3), method: "test", params: .object([:])))
                )
            }

            let error = try await errorPromise.task.value
            #expect(MCPClientError.isInstance(error))
            let message = (error as? MCPClientError)?.message ?? String(describing: error)
            #expect(message.contains("POSTing to endpoint"))
        } catch {
            controller.finish()
            try? await transport.close()
            throw error
        }

        controller.finish()
        try await transport.close()
    }

    @Test("should handle invalid JSON-RPC messages from inbound SSE")
    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    func handleInvalidJSONRPCFromInboundSSE() async throws {
        let endExclusive = TestURLProtocol.beginExclusiveAccess()
        defer { endExclusive() }
        TestURLProtocol.reset()
        let session = makeTestSession()

        let mcpUrl = "http://localhost:4000/mcp"
        let controller = TestURLProtocol.makeController()

        TestURLProtocol.requestHandler = { request, _ in
            let url = normalizeTestURL(try #require(request.url?.absoluteString))
            let method = request.httpMethod ?? "GET"
            guard url == mcpUrl else { return .empty(status: 404) }

            if method == "GET" {
                return .stream(
                    status: 200,
                    headers: ["content-type": "text/event-stream"],
                    controller: controller
                )
            }

            return .empty(status: 404)
        }

        let transport = try HttpMCPTransport(config: MCPTransportConfig(type: "http", url: mcpUrl), session: session)
        do {
            let errorPromise = createResolvablePromise(of: Error.self)
            transport.onerror = { error in
                errorPromise.resolve(error)
            }

            try await transport.start()

            controller.write("event: message\ndata: {\"foo\":\"bar\"}\n\n")

            let error = try await errorPromise.task.value
            #expect(MCPClientError.isInstance(error))
            let message = (error as? MCPClientError)?.message ?? String(describing: error)
            #expect(message.contains("Failed to parse message"))
        } catch {
            controller.finish()
            try? await transport.close()
            throw error
        }

        controller.finish()
        try await transport.close()
    }

    @Test("should handle non-JSON-RPC response for notifications")
    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    func handleNonJSONRPCResponseForNotifications() async throws {
        let endExclusive = TestURLProtocol.beginExclusiveAccess()
        defer { endExclusive() }
        TestURLProtocol.reset()
        let session = makeTestSession()

        let mcpUrl = "http://localhost:4000/mcp"

        TestURLProtocol.requestHandler = { request, _ in
            let url = normalizeTestURL(try #require(request.url?.absoluteString))
            let method = request.httpMethod ?? "GET"
            guard url == mcpUrl else { return .empty(status: 404) }

            switch method {
            case "GET":
                return .empty(status: 405)
            case "POST":
                return .jsonValue(
                    status: 200,
                    headers: ["content-type": "application/json"],
                    body: .object(["ok": .bool(true)])
                )
            default:
                return .empty(status: 404)
            }
        }

        let transport = try HttpMCPTransport(config: MCPTransportConfig(type: "http", url: mcpUrl), session: session)

        do {
            try await transport.start()

            let notification = JSONRPCMessage.notification(
                JSONRPCNotification(method: "notifications/initialized", params: nil)
            )

            try await transport.send(message: notification)
        } catch {
            try? await transport.close()
            throw error
        }

        try await transport.close()
    }

    @Test("should send custom headers with all requests")
    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    func sendCustomHeaders() async throws {
        let endExclusive = TestURLProtocol.beginExclusiveAccess()
        defer { endExclusive() }
        TestURLProtocol.reset()
        let session = makeTestSession()

        let mcpUrl = "http://localhost:4000/mcp"
        let customHeaders = [
            "authorization": "Bearer test-token",
            "x-custom-header": "test-value",
        ]

        TestURLProtocol.requestHandler = { request, _ in
            let url = normalizeTestURL(try #require(request.url?.absoluteString))
            let method = request.httpMethod ?? "GET"
            guard url == mcpUrl else { return .empty(status: 404) }

            if method == "GET" {
                return .empty(status: 405)
            }

            if method == "POST" {
                return .jsonValue(
                    status: 200,
                    headers: ["content-type": "application/json"],
                    body: .object([
                        "jsonrpc": .string("2.0"),
                        "id": .number(1),
                        "result": .object(["ok": .bool(true)]),
                    ])
                )
            }

            return .empty(status: 404)
        }

        let transport = try HttpMCPTransport(
            config: MCPTransportConfig(type: "http", url: mcpUrl, headers: customHeaders),
            session: session
        )
        do {
            try await transport.start()

            try await transport.send(
                message: .request(JSONRPCRequest(id: .string("1"), method: "test", params: .object(["foo": .string("bar")])))
            )

            let calls = TestURLProtocol.takeCalls()

            let get = try #require(
                calls.first(where: { $0.requestMethod == "GET" && normalizeTestURL($0.requestUrl) == mcpUrl })
            )
            #expect(get.requestHeaders["mcp-protocol-version"] == LATEST_PROTOCOL_VERSION)
            #expect(get.requestHeaders["accept"] == "text/event-stream")
            #expect(get.requestHeaders["authorization"] == "Bearer test-token")
            #expect(get.requestHeaders["x-custom-header"] == "test-value")
            #expect(get.requestUserAgent?.contains("ai-sdk/") == true)

            let post = try #require(
                calls.first(where: { $0.requestMethod == "POST" && normalizeTestURL($0.requestUrl) == mcpUrl })
            )
            #expect(post.requestHeaders["mcp-protocol-version"] == LATEST_PROTOCOL_VERSION)
            #expect(post.requestHeaders["accept"] == "application/json, text/event-stream")
            #expect(post.requestHeaders["content-type"] == "application/json")
            #expect(post.requestHeaders["authorization"] == "Bearer test-token")
            #expect(post.requestHeaders["x-custom-header"] == "test-value")
            #expect(post.requestUserAgent?.contains("ai-sdk/") == true)
        } catch {
            try? await transport.close()
            throw error
        }

        try await transport.close()
    }
}
