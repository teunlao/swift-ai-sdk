import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import XAIProvider

@Suite("XAITranscriptionModel")
struct XAITranscriptionModelTests {
    private final class Socket: XAIWebSocketConnection, @unchecked Sendable {
        let messages: AsyncThrowingStream<String, Error>
        private let continuation: AsyncThrowingStream<String, Error>.Continuation
        private let events: [String]
        private let lock = NSLock()
        private var audio: [Data] = []
        init(events: [String]) {
            let pair = AsyncThrowingStream<String, Error>.makeStream()
            messages = pair.stream; continuation = pair.continuation; self.events = events
            continuation.yield(#"{"type":"transcript.created"}"#)
        }
        func send(_ message: XAIWebSocketMessage) async throws {
            switch message {
            case .binary(let data): lock.withLock { audio.append(data) }
            case .text(let text):
                #expect(text == #"{"type":"audio.done"}"#)
                for event in events { continuation.yield(event) }
                continuation.finish()
            }
        }
        func close(code: Int?) { continuation.finish() }
        var audioBytes: [Data] { lock.withLock { audio } }
    }

    @Test("multipart transcription sends model/options before audio and returns diarized words")
    func generate() async throws {
        let provider = createXai(settings: .init(apiKey: "key", fetch: { request in
            #expect(request.url?.path == "/v1/stt")
            let body = String(decoding: request.httpBody!, as: UTF8.self)
            let model = try #require(body.range(of: "name=\"model\""))
            let file = try #require(body.range(of: "name=\"file\""))
            #expect(model.lowerBound < file.lowerBound)
            #expect(body.contains("grok-voice-transcribe-2.0"))
            #expect(body.contains("filename=\"audio.wav\""))
            #expect(body.contains("name=\"audio_format\""))
            #expect(body.contains("name=\"diarize\""))
            let payload = #"{"text":"hello","language":"en","duration":1.5,"words":[{"text":"hello","start":0,"end":1.5,"speaker":1}]}"#
            return FetchResponse(body: .data(Data(payload.utf8)), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
        }))
        let result = try await provider.transcription(modelId: .grokVoiceTranscribe20).doGenerate(options: .init(audio: .base64("AQID"), mediaType: "audio/wav", providerOptions: ["xai": ["audioFormat": .string("pcm"), "sampleRate": .number(16000), "diarize": .bool(true), "keyterm": .array([.string("hello"), .string("world")])]]))
        #expect(result.text == "hello")
        #expect(result.language == "en")
        #expect(result.durationInSeconds == 1.5)
        #expect(result.segments == [.init(text: "hello", startSecond: 0, endSecond: 1.5)])
        #expect(result.providerMetadata?["xai"]?["words"] == .array([.object(["text": .string("hello"), "start": .number(0), "end": .number(1.5), "speaker": .number(1)])]))
    }

    @Test("streaming preserves revisable text, utterance finals, multichannel order and audio encoding")
    func streaming() async throws {
        let socket = Socket(events: [
            #"{"type":"transcript.partial","channel_index":1,"text":"draft","is_final":true,"speech_final":false,"start":0,"duration":1}"#,
            #"{"type":"transcript.partial","channel_index":1,"text":"second","is_final":true,"speech_final":true,"start":0,"duration":1}"#,
            #"{"type":"transcript.partial","channel_index":0,"text":"first","is_final":true,"speech_final":true,"start":0,"duration":1}"#,
            #"{"type":"transcript.partial","channel_index":0,"text":"tail","is_final":false,"start":1,"duration":1}"#,
            #"{"type":"transcript.done","channel_index":1,"text":"","duration":1}"#,
            #"{"type":"transcript.done","channel_index":0,"text":"","duration":2}"#
        ])
        let provider = createXai(settings: .init(baseURL: "https://example.com/v1", apiKey: "key", webSocket: { request in
            #expect(request.url?.scheme == "wss")
            #expect(request.url?.path == "/v1/stt")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer key")
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            #expect(query.contains(.init(name: "encoding", value: "mulaw")))
            #expect(query.contains(.init(name: "sample_rate", value: "8000")))
            #expect(query.filter { $0.name == "keyterm" }.map(\.value) == ["one", "two"])
            return socket
        }))
        let audio = AsyncThrowingStream<TranscriptionModelV4StreamAudio, Error> { continuation in continuation.yield(.base64("AQID")); continuation.finish() }
        let result = try await provider.transcription().doStream(options: .init(audio: audio, inputAudioFormat: .init(type: "audio/pcmu", rate: 8000), providerOptions: ["xai": ["multichannel": .bool(true), "channels": .number(2), "language": .string("en"), "keyterm": .array([.string("one"), .string("two")])]], includeRawChunks: true))
        var parts: [TranscriptionModelV4StreamPart] = []
        for try await part in result.stream { parts.append(part) }
        #expect(socket.audioBytes == [Data([1, 2, 3])])
        #expect(parts.contains(.transcriptPartial(id: "channel-1", text: "draft", startSecond: 0, durationInSeconds: 1, channelIndex: 1, providerMetadata: nil)))
        #expect(parts.contains(.transcriptFinal(id: "channel-1", text: "second", startSecond: 0, endSecond: 1, channelIndex: 1, providerMetadata: nil)))
        #expect(parts.last == .finish(text: "first tail\nsecond", segments: [], language: "en", durationInSeconds: 2, providerMetadata: nil))
    }

    @Test("streaming multichannel requires an explicit channel count")
    func channelsRequired() async throws {
        let provider = createXai(settings: .init(apiKey: "key", webSocket: { _ in Issue.record("Invalid options cannot connect"); throw CancellationError() }))
        await #expect(throws: InvalidArgumentError.self) {
            _ = try await provider.transcription().doStream(options: .init(audio: AsyncThrowingStream { $0.finish() }, inputAudioFormat: .init(type: "audio/pcm"), providerOptions: ["xai": ["multichannel": .bool(true)]]))
        }
    }

    @Test("connection failures release the caller's audio producer")
    func failedConnectionReleasesAudio() async throws {
        let cancellation = AsyncStream<Void>.makeStream()
        let audio = AsyncThrowingStream<TranscriptionModelV4StreamAudio, Error>.makeStream()
        audio.continuation.onTermination = { _ in cancellation.continuation.yield(()); cancellation.continuation.finish() }
        let provider = createXai(settings: .init(apiKey: "key", webSocket: { _ in throw URLError(.cannotConnectToHost) }))
        let result = try await provider.transcription().doStream(options: .init(audio: audio.stream, inputAudioFormat: .init(type: "audio/pcm")))
        await #expect(throws: URLError.self) { for try await _ in result.stream {} }
        var iterator = cancellation.stream.makeAsyncIterator()
        #expect(await iterator.next() != nil)
    }
}
