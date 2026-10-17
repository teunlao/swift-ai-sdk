#if canImport(Network)
import Foundation
import CryptoKit
import Testing
import AISDKProviderUtils

@Suite("Native WebSocket transport")
struct WebSocketNativeTests {
    @Test("URLSession delivers ordered text, binary, and typed close diagnostics")
    func nativeFrames() async throws {
        let completed = AsyncStream<Void>.makeStream()
        let server = try await LoopbackHTTPServer { connection in
            defer { completed.continuation.finish() }
            do {
                let request = try await connection.readRequest()
                #expect(request.path == "/stream")
                #expect(request.headers["authorization"] == "Bearer loopback-key")
                #expect(request.headers["sec-websocket-protocol"] == "transcription")
                let key = try #require(request.headers["sec-websocket-key"])
                let digest = Insecure.SHA1.hash(data: Data((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").utf8))
                try await connection.sendHead(status: 101, headers: [
                    "Connection": "Upgrade", "Upgrade": "websocket", "Sec-WebSocket-Accept": Data(digest).base64EncodedString(),
                    "Sec-WebSocket-Protocol": "transcription",
                ])
                var frames = Data([0x81, 5])
                frames.append(Data("first".utf8))
                frames.append(contentsOf: [0x82, 6])
                frames.append(Data("second".utf8))
                frames.append(contentsOf: [0x88, 2, 0x03, 0xE8])
                try await connection.send(frames)
                await connection.close()
            } catch { Issue.record(error) }
        }
        defer { server.stop() }
        let url = try toWebSocketURL(server.origin + "/stream")
        let connection = try connectToWebSocket(
            url: url.absoluteString, protocols: ["transcription"], headers: ["Authorization": "Bearer loopback-key"]
        )
        var received: [String] = []
        do {
            for try await text in connection.messages { received.append(text) }
            Issue.record("The close frame was not reported")
        } catch let error as WebSocketError {
            #expect(error == .closed(code: 1000, reason: ""))
        }
        #expect(received == ["first", "second"])
        for await _ in completed.stream {}
    }
}
#endif
