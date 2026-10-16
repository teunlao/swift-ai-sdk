#if os(macOS) || os(Linux)
import Testing
import Foundation
import SwiftAISDK
import AISDKProvider

@Suite("StdioMCPTransport", .serialized)
struct StdioMCPTransportTests {
    @Test("Stdio frames complete lines and reports a closed stdin without terminating the host")
    func lineFraming() async throws {
        let script = "IFS= read -r line; printf '%s\\n' \"$line\"; exec 0<&-; printf '{\"jsonrpc\":\"2.0\",\"method\":\"stdin-closed\"}\\n'; exec /bin/sleep 30"
        let transport = StdioMCPTransport(.init(command: "/bin/sh", args: ["-c", script]))
        defer { Task { try? await transport.close() } }
        let response = createResolvablePromise(of: JSONRPCMessage.self)
        let ready = createResolvablePromise(of: Bool.self)
        let failure = ErrorBox()
        transport.onmessage = { message in
            if case .notification(let notification) = message, notification.method == "stdin-closed" { ready.resolve(true) }
            else { response.resolve(message) }
        }
        transport.onerror = { failure.set($0) }
        try await transport.start()
        try await transport.send(message: .request(.init(id: .string("call-1"), method: "tools/call", params: .object(["name": .string("echo"), "arguments": .object(["text": .string("first\nsecond")])]))))
        let result = try await response.task.value
        guard case .request(let request) = result else { Issue.record("Expected the framed request"); try await transport.close(); return }
        #expect(request.id == .string("call-1"))
        #expect(request.params == .object(["name": .string("echo"), "arguments": .object(["text": .string("first\nsecond")])]))
        #expect(try await ready.task.value)
        do {
            try await transport.send(message: .notification(.init(method: "ping")))
            Issue.record("A closed stdin accepted a message")
        } catch {
            #expect((error as NSError).domain == NSPOSIXErrorDomain)
            #expect((error as NSError).code == Int(POSIXErrorCode.EPIPE.rawValue))
        }
        let error = failure.get().map { $0 as NSError }
        #expect(error?.domain == NSPOSIXErrorDomain)
        #expect(error?.code == Int(POSIXErrorCode.EPIPE.rawValue))
        try await transport.close()
        await #expect(throws: CancellationError.self) { try await transport.start() }
    }

    @Test("Explicit environment values override inherited defaults in the child")
    func environmentPrecedence() async throws {
        let script = "printf '{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"home\":\"%s\",\"path\":\"%s\"}}\\n' \"$HOME\" \"$PATH\""
        let transport = StdioMCPTransport(.init(command: "/bin/sh", args: ["-c", script], env: ["HOME": "/custom/home", "PATH": "/custom/bin"]))
        let response = createResolvablePromise(of: JSONRPCMessage.self)
        let delivered = BoolBox(false)
        let closed = createResolvablePromise(of: Bool.self)
        transport.onmessage = { delivered.set(true); response.resolve($0) }
        transport.onclose = { closed.resolve(delivered.get()) }
        try await transport.start()
        let result = try await response.task.value
        guard case .response(let message) = result else { Issue.record("Expected child environment response"); try await transport.close(); return }
        #expect(message.result == .object(["home": .string("/custom/home"), "path": .string("/custom/bin")]))
        #expect(try await closed.task.value)
        try await transport.close()
    }
}
#endif
