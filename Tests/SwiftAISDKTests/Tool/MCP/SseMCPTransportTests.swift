/**
 Tests for SseMCPTransport.

 Port of `packages/mcp/src/tool/mcp-sse-transport.test.ts`.
 */

import Foundation
import Testing

@testable import SwiftAISDK
@testable import AISDKProvider
import AISDKProviderUtils

@Suite("SseMCPTransport", .serialized)
struct SseMCPTransportTests {

    @Test("should establish connection and receive endpoint")
    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    func establishConnectionAndReceiveEndpoint() async throws {
        let endExclusive = TestURLProtocol.beginExclusiveAccess()
        defer { endExclusive() }
        TestURLProtocol.reset()
        let session = makeTestSession()

        let controller = TestURLProtocol.makeController()
        let sseUrl = "http://localhost:3000/sse"
        let messagesUrl = "http://localhost:3000/messages"

        TestURLProtocol.requestHandler = { request, _ in
            let url = normalizeTestURL(try #require(request.url?.absoluteString))
            switch (request.httpMethod ?? "GET", url) {
            case ("GET", sseUrl):
                return .stream(
                    status: 200,
                    headers: ["content-type": "text/event-stream"],
                    controller: controller
                )
            default:
                return .empty(status: 404)
            }
        }

        let transport = try SseMCPTransport(config: MCPTransportConfig(url: sseUrl), session: session)

        do {
            async let connect: Void = transport.start()
            controller.write("event: endpoint\ndata: \(messagesUrl)\n\n")
            try await connect
        } catch {
            try? await transport.close()
            throw error
        }

        try await transport.close()

        let calls = TestURLProtocol.takeCalls()
        #expect(calls.count == 1)
        let call = try #require(calls.first)
        #expect(call.requestMethod == "GET")
        #expect(normalizeTestURL(call.requestUrl) == sseUrl)
        #expect(call.requestHeaders["mcp-protocol-version"] == LATEST_PROTOCOL_VERSION)
        #expect(call.requestHeaders["accept"] == "text/event-stream")
    }

    @Test("should throw if server returns non-200 status")
    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    func throwIfServerReturnsNon200() async throws {
        let endExclusive = TestURLProtocol.beginExclusiveAccess()
        defer { endExclusive() }
        TestURLProtocol.reset()
        let session = makeTestSession()

        let sseUrl = "http://localhost:3000/sse"
        TestURLProtocol.requestHandler = { request, _ in
            let url = normalizeTestURL(try #require(request.url?.absoluteString))
            switch (request.httpMethod ?? "GET", url) {
            case ("GET", sseUrl):
                return .empty(status: 500)
            default:
                return .empty(status: 404)
            }
        }

        let transport = try SseMCPTransport(config: MCPTransportConfig(url: sseUrl), session: session)
        await #expect(throws: Error.self) {
            try await transport.start()
        }

        try? await transport.close()
    }

    @Test("should handle valid JSON-RPC messages")
    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    func handleValidJSONRPCMessages() async throws {
        let endExclusive = TestURLProtocol.beginExclusiveAccess()
        defer { endExclusive() }
        TestURLProtocol.reset()
        let session = makeTestSession()

        let controller = TestURLProtocol.makeController()
        let sseUrl = "http://localhost:3000/sse"
        let messagesUrl = "http://localhost:3000/messages"

        TestURLProtocol.requestHandler = { request, _ in
            let url = normalizeTestURL(try #require(request.url?.absoluteString))
            switch (request.httpMethod ?? "GET", url) {
            case ("GET", sseUrl):
                return .stream(
                    status: 200,
                    headers: ["content-type": "text/event-stream"],
                    controller: controller
                )
            default:
                return .empty(status: 404)
            }
        }

        let transport = try SseMCPTransport(config: MCPTransportConfig(url: sseUrl), session: session)

        let messagePromise = createResolvablePromise(of: JSONRPCMessage.self)
        transport.onmessage = { msg in
            messagePromise.resolve(msg)
        }

        do {
            async let connect: Void = transport.start()
            controller.write("event: endpoint\ndata: \(messagesUrl)\n\n")
            try await connect
        } catch {
            try? await transport.close()
            throw error
        }

        let testMessage = JSONRPCMessage.request(
            JSONRPCRequest(
                id: .string("1"),
                method: "test",
                params: .object(["foo": .string("bar")])
            )
        )

        let payload = String(data: try JSONEncoder().encode(testMessage), encoding: .utf8)!
        controller.write("data: \(payload)\n\n")

        let received = try await messagePromise.task.value
        guard case .request(let request) = received else {
            Issue.record("Expected request message")
            try? await transport.close()
            return
        }

        #expect(request.method == "test")
        #expect(request.id == .string("1"))
        #expect(request.params == .object(["foo": .string("bar")]))

        try await transport.close()
    }

    @Test("should handle invalid JSON-RPC messages")
    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    func handleInvalidJSONRPCMessages() async throws {
        let endExclusive = TestURLProtocol.beginExclusiveAccess()
        defer { endExclusive() }
        TestURLProtocol.reset()
        let session = makeTestSession()

        let controller = TestURLProtocol.makeController()
        let sseUrl = "http://localhost:3000/sse"
        let messagesUrl = "http://localhost:3000/messages"

        TestURLProtocol.requestHandler = { request, _ in
            let url = normalizeTestURL(try #require(request.url?.absoluteString))
            switch (request.httpMethod ?? "GET", url) {
            case ("GET", sseUrl):
                return .stream(
                    status: 200,
                    headers: ["content-type": "text/event-stream"],
                    controller: controller
                )
            default:
                return .empty(status: 404)
            }
        }

        let transport = try SseMCPTransport(config: MCPTransportConfig(url: sseUrl), session: session)

        let errorPromise = createResolvablePromise(of: Error.self)
        transport.onerror = { err in
            errorPromise.resolve(err)
        }

        do {
            async let connect: Void = transport.start()
            controller.write("event: endpoint\ndata: \(messagesUrl)\n\n")
            try await connect
        } catch {
            try? await transport.close()
            throw error
        }

        controller.write("event: message\ndata: {\"foo\":\"bar\"}\n\n")

        let error = try await errorPromise.task.value
        #expect(MCPClientError.isInstance(error))
        let message = (error as? MCPClientError)?.message ?? String(describing: error)
        #expect(message.contains("Failed to parse message"))

        try await transport.close()
    }

    @Test("should send messages as POST requests")
    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    func sendMessagesAsPOST() async throws {
        let sseUrl = "https://mcp.example.com/sse"
        let messagesUrl = "https://mcp.example.com/messages"
        let stream = AsyncThrowingStream<Data, Error>.makeStream()
        defer { stream.continuation.finish() }
        stream.continuation.yield(Data("event: endpoint\ndata: \(messagesUrl)\n\n".utf8))
        let posted = createResolvablePromise(of: JSONValue.self)
        let fetch: FetchFunction = { request in
            let url = try #require(request.url)
            if request.httpMethod == "POST" {
                #expect(url.absoluteString == messagesUrl)
                posted.resolve(try decodeJSONValue(from: #require(request.httpBody)))
                return FetchResponse(body: .none, urlResponse: try #require(HTTPURLResponse(url: url, statusCode: 201, httpVersion: nil, headerFields: nil)))
            }
            #expect(request.httpMethod == "GET")
            #expect(url.absoluteString == sseUrl)
            return FetchResponse(body: .stream(stream.stream), urlResponse: try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["content-type": "text/event-stream"])))
        }
        let transport = try SseMCPTransport(config: .init(url: sseUrl, fetch: fetch))
        try await transport.start()
        let message = JSONRPCMessage.request(.init(id: .string("1"), method: "test", params: .object(["foo": .string("bar")])))
        try await transport.send(message: message)
        #expect(try await posted.task.value == decodeJSONValue(from: JSONEncoder().encode(message)))
        try await transport.close()
    }

    @Test("should handle POST request errors")
    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    func handlePOSTRequestErrors() async throws {
        let endExclusive = TestURLProtocol.beginExclusiveAccess()
        defer { endExclusive() }
        TestURLProtocol.reset()
        let session = makeTestSession()

        let controller = TestURLProtocol.makeController()
        let sseUrl = "http://localhost:3000/sse"
        let messagesUrl = "http://localhost:3000/messages"

        let shouldFailPost = TestURLProtocol.LockedValue(true)

        TestURLProtocol.requestHandler = { request, _ in
            let url = normalizeTestURL(try #require(request.url?.absoluteString))
            switch (request.httpMethod ?? "GET", url) {
            case ("GET", sseUrl):
                return .stream(
                    status: 200,
                    headers: ["content-type": "text/event-stream"],
                    controller: controller
                )
            case ("POST", messagesUrl):
                if shouldFailPost.get() {
                    return .data(
                        status: 500,
                        headers: ["content-type": "text/plain"],
                        body: Data("Internal Server Error".utf8)
                    )
                }

                return .empty(status: 201)
            default:
                return .empty(status: 404)
            }
        }

        let transport = try SseMCPTransport(config: MCPTransportConfig(url: sseUrl), session: session)

        let errorPromise = createResolvablePromise(of: Error.self)
        transport.onerror = { error in
            errorPromise.resolve(error)
        }

        do {
            async let connect: Void = transport.start()
            controller.write("event: endpoint\ndata: \(messagesUrl)\n\n")
            try await connect
        } catch {
            try? await transport.close()
            throw error
        }

        let message = JSONRPCMessage.request(
            JSONRPCRequest(
                id: .string("1"),
                method: "test",
                params: .object(["foo": .string("bar")])
            )
        )

        await #expect(throws: MCPClientError.self) { try await transport.send(message: message) }
        let error = try #require(try await errorPromise.task.value as? MCPClientError)
        #expect(error.statusCode == 500)
        #expect(error.url == messagesUrl)
        #expect(error.responseBody == "Internal Server Error")

        shouldFailPost.set(false)
        try await transport.send(message: message)

        let post = try #require(TestURLProtocol.takeCalls().last { $0.requestMethod == "POST" })
        #expect(try decodeJSONValue(from: #require(post.requestBody)) == decodeJSONValue(from: JSONEncoder().encode(message)))

        try await transport.close()
    }

    @Test("should send custom headers with all requests")
    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    func sendCustomHeaders() async throws {
        let endExclusive = TestURLProtocol.beginExclusiveAccess()
        defer { endExclusive() }
        TestURLProtocol.reset()
        let session = makeTestSession()

        let controller = TestURLProtocol.makeController()
        let sseUrl = "http://localhost:3000/sse"
        let messagesUrl = "http://localhost:3000/messages"

        let customHeaders = [
            "authorization": "Bearer test-token",
            "x-custom-header": "test-value",
        ]

        TestURLProtocol.requestHandler = { request, _ in
            let url = normalizeTestURL(try #require(request.url?.absoluteString))
            switch (request.httpMethod ?? "GET", url) {
            case ("GET", sseUrl):
                return .stream(
                    status: 200,
                    headers: ["content-type": "text/event-stream"],
                    controller: controller
                )
            case ("POST", messagesUrl):
                return .empty(status: 201)
            default:
                return .empty(status: 404)
            }
        }

        let transport = try SseMCPTransport(
            config: MCPTransportConfig(url: sseUrl, headers: customHeaders),
            session: session
        )

        do {
            async let connect: Void = transport.start()
            controller.write("event: endpoint\ndata: \(messagesUrl)\n\n")
            try await connect
        } catch {
            try? await transport.close()
            throw error
        }

        let message = JSONRPCMessage.request(
            JSONRPCRequest(
                id: .string("1"),
                method: "test",
                params: .object(["foo": .string("bar")])
            )
        )

        try await transport.send(message: message)

        let calls = TestURLProtocol.takeCalls()
        #expect(calls.count == 2)

        let get = calls[0]
        #expect(get.requestHeaders["mcp-protocol-version"] == LATEST_PROTOCOL_VERSION)
        #expect(get.requestHeaders["accept"] == "text/event-stream")
        #expect(get.requestHeaders["authorization"] == "Bearer test-token")
        #expect(get.requestHeaders["x-custom-header"] == "test-value")
        #expect(get.requestUserAgent?.contains("ai-sdk/") == true)

        let post = calls[1]
        #expect(post.requestHeaders["mcp-protocol-version"] == LATEST_PROTOCOL_VERSION)
        #expect(post.requestHeaders["content-type"] == "application/json")
        #expect(post.requestHeaders["authorization"] == "Bearer test-token")
        #expect(post.requestHeaders["x-custom-header"] == "test-value")
        #expect(post.requestUserAgent?.contains("ai-sdk/") == true)

        try await transport.close()
    }
}
