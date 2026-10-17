import Foundation
import Testing
import AISDKProviderUtils

@Suite("WebSocket transport")
struct WebSocketTests {
    private enum Failure: Error { case transport, constructor }

    private actor Gate {
        private var opened = false
        private var waiters: [CheckedContinuation<Void, Never>] = []
        var isOpen: Bool { opened }

        func wait() async {
            if opened { return }
            await withCheckedContinuation { waiters.append($0) }
        }

        func open() {
            opened = true
            let pending = waiters
            waiters = []
            for waiter in pending { waiter.resume() }
        }
    }

    private final class Iterator: @unchecked Sendable {
        private var iterator: AsyncThrowingStream<WebSocketMessage, Error>.Iterator
        init(_ stream: AsyncThrowingStream<WebSocketMessage, Error>) { iterator = stream.makeAsyncIterator() }
        func next() async throws -> WebSocketMessage? { try await iterator.next() }
    }

    private final class Socket: WebSocketLike, @unchecked Sendable {
        let messages: AsyncThrowingStream<WebSocketMessage, Error>
        let input: AsyncThrowingStream<WebSocketMessage, Error>.Continuation
        let readStarted = Gate()
        let sendStarted = Gate()
        let releaseSend = Gate()
        private let lock = NSLock()
        private var closes: [Int?] = []
        var closeCodes: [Int?] { lock.withLock { closes } }

        init() {
            let pair = AsyncThrowingStream<WebSocketMessage, Error>.makeStream()
            input = pair.continuation
            let iterator = Iterator(pair.stream)
            let started = readStarted
            messages = AsyncThrowingStream(unfolding: {
                await started.open()
                return try await iterator.next()
            })
        }

        func send(_ message: WebSocketMessage) async throws {
            await sendStarted.open()
            await releaseSend.wait()
        }

        func close(code: Int?) {
            lock.withLock { closes.append(code) }
            input.finish()
            let gate = releaseSend
            Task { await gate.open() }
        }
    }

    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var stored = false
        var value: Bool { lock.withLock { stored } }
        func set() { lock.withLock { stored = true } }
    }

    @Test("Text and binary frames are decoded in order before a transport failure")
    func messageOrder() async throws {
        let socket = Socket()
        let connection = try connectToWebSocket(url: "wss://example.com/socket", webSocket: { _ in socket })
        socket.input.yield(.text("first"))
        socket.input.yield(.binary(Data([0xE2, 0x82, 0xAC, 0xFF])))
        socket.input.finish(throwing: Failure.transport)
        var received: [String] = []
        do {
            for try await message in connection.messages { received.append(message) }
            Issue.record("Expected transport failure")
        } catch Failure.transport {
            #expect(received == ["first", "€�"])
        }
    }

    @Test("Close unblocks an outstanding read and preserves its first close code")
    func closePendingRead() async throws {
        let socket = Socket()
        let connection = try connectToWebSocket(url: "wss://example.com/socket", webSocket: { _ in socket })
        let reader = Task {
            var iterator = connection.messages.makeAsyncIterator()
            return try await iterator.next()
        }
        await socket.readStarted.wait()
        connection.close(code: 1008)
        #expect(try await reader.value == nil)
        connection.close(code: 1000)
        #expect(socket.closeCodes == [1008])
    }

    @Test("Cancelling a consumer closes its transport and finishes its pending read")
    func cancellation() async throws {
        let socket = Socket()
        let connection = try connectToWebSocket(url: "wss://example.com/socket", webSocket: { _ in socket })
        let reader = Task {
            var iterator = connection.messages.makeAsyncIterator()
            return try await iterator.next()
        }
        await socket.readStarted.wait()
        reader.cancel()
        await #expect(throws: CancellationError.self) { _ = try await reader.value }
        #expect(socket.closeCodes.count == 1)
    }

    @Test("Abort signals terminate a suspended read without an incoming frame")
    func abort() async throws {
        let socket = Socket()
        let flag = Flag()
        let connection = try connectToWebSocket(
            url: "wss://example.com/socket", webSocket: { _ in socket }, abortSignal: { flag.value }
        )
        let reader = Task {
            var iterator = connection.messages.makeAsyncIterator()
            return try await iterator.next()
        }
        await socket.readStarted.wait()
        flag.set()
        await #expect(throws: CancellationError.self) { _ = try await reader.value }
        #expect(socket.closeCodes.count == 1)
    }

    @Test("An already-aborted request never constructs a transport")
    func alreadyAborted() throws {
        #expect(throws: CancellationError.self) {
            try connectToWebSocket(
                url: "wss://example.com/socket", webSocket: { _ in throw Failure.constructor }, abortSignal: { true }
            )
        }
    }

    @Test("Send completion follows the transport's backpressure")
    func sendBackpressure() async throws {
        let socket = Socket()
        let completed = Gate()
        let connection = try connectToWebSocket(url: "wss://example.com/socket", webSocket: { _ in socket })
        let send = Task {
            try await connection.send(.binary(Data([1, 2, 3])))
            await completed.open()
        }
        await socket.sendStarted.wait()
        #expect(await completed.isOpen == false)
        await socket.releaseSend.open()
        try await send.value
        #expect(await completed.isOpen)
        connection.close()
    }

    @Test("Cancelling a blocked send closes the connection and releases the sender")
    func cancelPendingSend() async throws {
        let socket = Socket()
        let connection = try connectToWebSocket(url: "wss://example.com/socket", webSocket: { _ in socket })
        let send = Task { try await connection.send(.text("audio-done")) }
        await socket.sendStarted.wait()
        send.cancel()
        await #expect(throws: CancellationError.self) { try await send.value }
        #expect(socket.closeCodes.count == 1)
    }

    @Test("Connection construction preserves headers and requested subprotocols")
    func requestBoundary() throws {
        let socket = Socket()
        let connection = try connectToWebSocket(
            url: "wss://example.com/socket?model=transcribe",
            protocols: ["transcription", "auth.token"],
            headers: ["Authorization": "Bearer key", "x-empty": "", "x-absent": nil],
            webSocket: { request in
                #expect(request.url?.absoluteString == "wss://example.com/socket?model=transcribe")
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer key")
                #expect(request.value(forHTTPHeaderField: "x-empty") == "")
                #expect(request.value(forHTTPHeaderField: "x-absent") == nil)
                #expect(request.value(forHTTPHeaderField: "Sec-WebSocket-Protocol") == "transcription, auth.token")
                return socket
            }
        )
        connection.close()
        #expect(throws: Failure.self) {
            try connectToWebSocket(url: "wss://example.com/socket", webSocket: { _ in throw Failure.constructor })
        }
    }
}
