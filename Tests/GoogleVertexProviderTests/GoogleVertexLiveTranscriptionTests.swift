import Foundation
import Testing
import AISDKProvider
import GoogleProvider
import GoogleVertexProvider

@Suite("Vertex live transcription")
struct GoogleVertexLiveTranscriptionTests {
    @Test func authenticatesRegionalLiveStream() async throws {
        let socket = VertexLiveSocket()
        let requests = VertexLiveRequests()
        let server = Task {
            for await value in socket.sent {
                guard case .object(let event) = value else { continue }
                if let setup = event["setup"] {
                    #expect(setup == .object([
                        "model": .string("projects/project/locations/eu/publishers/google/models/gemini-3.5-transcribe-live"),
                        "inputAudioTranscription": .object(["mode": .string("SMART")])
                    ]))
                    socket.emit(#"{"setupComplete":{}}"#)
                }
                if case .object(let realtime) = event["realtimeInput"], realtime["audioStreamEnd"] == .bool(true) {
                    socket.emit(#"{"serverContent":{"inputTranscription":{"text":"Vertex transcript","languageCode":"de","finished":true}},"usageMetadata":{"totalTokenCount":2}}"#)
                    socket.emit(#"{"serverContent":{"interactionStatus":"IDLE"}}"#)
                    return
                }
            }
        }
        defer { server.cancel() }
        let provider = createGoogleVertex(settings: .init(location: "eu", project: "project", accessTokenProvider: { "oauth-token" }, webSocket: { request in
            requests.store(request); return socket
        }))
        let model = provider.transcription(modelId: "gemini-3.5-transcribe-live")
        let audio = AsyncThrowingStream<TranscriptionModelV4StreamAudio, Error> { $0.yield(.base64("AQID")); $0.finish() }
        let result = try await model.doStream(options: .init(audio: audio, inputAudioFormat: .init(type: "audio/pcm", rate: 16000), providerOptions: ["googleVertex": ["mode": .string("SMART")], "vertex": ["mode": .string("VERBATIM")]]))
        let parts = try await withThrowingTaskGroup(of: [TranscriptionModelV4StreamPart].self) { group in
            group.addTask { var parts: [TranscriptionModelV4StreamPart] = []; for try await part in result.stream { parts.append(part) }; return parts }
            group.addTask { try await Task.sleep(nanoseconds: 2_000_000_000); throw CancellationError() }
            defer { group.cancelAll() }
            return try await group.next() ?? []
        }
        #expect(parts.first == .streamStart(warnings: []))
        #expect(parts.contains(.transcriptFinal(id: "google-segment-0", text: "Vertex transcript", startSecond: nil, endSecond: nil, channelIndex: nil, providerMetadata: nil)))
        #expect(parts.last == .finish(text: "Vertex transcript", segments: [], language: "de", durationInSeconds: nil, usage: ["totalTokenCount": .number(2)], providerMetadata: ["google": ["usageMetadata": .object(["totalTokenCount": .number(2)])]]))
        let request = try #require(requests.value)
        #expect(request.url.absoluteString == "wss://aiplatform.eu.rep.googleapis.com/ws/google.cloud.aiplatform.v1.LlmBidiService/BidiGenerateContent")
        #expect(request.headers["Authorization"] == "Bearer oauth-token")
    }
}

private final class VertexLiveRequests: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: GoogleWebSocketRequest?
    func store(_ request: GoogleWebSocketRequest) { lock.lock(); defer { lock.unlock() }; stored = request }
    var value: GoogleWebSocketRequest? { lock.lock(); defer { lock.unlock() }; return stored }
}

private final class VertexLiveSocket: GoogleWebSocketConnection, Sendable {
    let messages: AsyncThrowingStream<String, Error>
    let sent: AsyncStream<JSONValue>
    private let incoming: AsyncThrowingStream<String, Error>.Continuation
    private let outgoing: AsyncStream<JSONValue>.Continuation
    init() {
        let received = AsyncThrowingStream<String, Error>.makeStream()
        messages = received.stream; incoming = received.continuation
        let sending = AsyncStream<JSONValue>.makeStream()
        sent = sending.stream; outgoing = sending.continuation
    }
    func send(_ text: String) async throws { outgoing.yield(try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))) }
    func emit(_ text: String) { incoming.yield(text) }
    func close(code: Int?) { incoming.finish(); outgoing.finish() }
}
