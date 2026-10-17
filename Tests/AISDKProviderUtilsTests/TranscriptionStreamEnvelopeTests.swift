import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils

@Suite("Transcription stream envelope")
struct TranscriptionStreamEnvelopeTests {
    @Test("Server parts round-trip their transcript, usage, metadata and error payloads", arguments: [
        TranscriptionModelV4StreamPart.streamStart(warnings: [.unsupported(feature: "timestamps", details: nil)]),
        .transcriptDelta(id: "segment-1", delta: "Hel", providerMetadata: ["provider": ["confidence": 0.9]]),
        .transcriptPartial(id: "segment-1", text: "Hel", startSecond: 0.1, durationInSeconds: 0.5, channelIndex: 1, providerMetadata: nil),
        .transcriptFinal(id: "segment-1", text: "Hello", startSecond: 0.1, endSecond: 0.6, channelIndex: 1, providerMetadata: nil),
        .finish(text: "Hello", segments: [.init(text: "Hello", startSecond: 0.1, endSecond: 0.6)], language: "en", durationInSeconds: 0.6, usage: ["tokens": 3], providerMetadata: ["provider": ["confidence": 0.9]]),
        .responseMetadata(timestamp: Date(timeIntervalSince1970: 1_767_225_600.125), modelId: "model-1", headers: ["x-request-id": "request-1"], body: ["recorded": true]),
        .raw(rawValue: .null),
        .error(error: ["name": "TypeError", "message": "Invalid input"]),
    ])
    func serverRoundTrip(part: TranscriptionModelV4StreamPart) throws {
        let frame = try #require(serializeTranscriptionStreamPart(part))
        #expect(parseTranscriptionStreamPart(frame) == part)
    }

    @Test("Client start frames encode options and permit provider-defined audio formats")
    func startFrame() throws {
        let frame = TranscriptionStreamStartFrame(
            inputAudioFormat: .init(type: "audio/future-format", rate: 16_000),
            providerOptions: ["provider": ["language": "en"]], includeRawChunks: false
        )
        let data = try JSONEncoder().encode(frame)
        #expect(try JSONDecoder().decode(JSONValue.self, from: data) == [
            "type": "transcription-stream.start", "inputAudioFormat": ["type": "audio/future-format", "rate": 16_000],
            "providerOptions": ["provider": ["language": "en"]], "includeRawChunks": false,
        ])
        #expect(parseTranscriptionStreamClientFrame(String(decoding: data, as: UTF8.self)) == .start(frame: frame))
        #expect(parseTranscriptionStreamClientFrame(#"{"type":"transcription-stream.audio-done"}"#) == .audioDone)
        #expect(parseTranscriptionStreamClientFrame(#"{"type":"transcription-stream.future"}"#) == .unknown)
    }

    @Test("Malformed and unsafe client frames are rejected before a session starts", arguments: [
        "{not json", "[]", #"{"type":3}"#,
        #"{"type":"transcription-stream.start","inputAudioFormat":{"type":"audio/pcm","rate":null}}"#,
        #"{"type":"transcription-stream.start","inputAudioFormat":{"type":"audio/pcm"},"providerOptions":null}"#,
        #"{"type":"transcription-stream.start","inputAudioFormat":{"type":"audio/pcm"},"includeRawChunks":1}"#,
        #"{"type":"transcription-stream.start","inputAudioFormat":{"type":"audio/pcm"},"__proto__":{"polluted":true}}"#,
    ])
    func invalidClientFrame(text: String) {
        guard case .invalid = parseTranscriptionStreamClientFrame(text) else {
            Issue.record("Expected invalid client frame")
            return
        }
    }

    @Test("Malformed, unsafe and unknown server parts are ignored", arguments: [
        "{not json", "[]", #"{"type":"future"}"#,
        #"{"type":"stream-start","warnings":[null]}"#,
        #"{"type":"transcript-delta","delta":"Hel","id":null}"#,
        #"{"type":"transcript-partial","text":"Hel","startSecond":"zero"}"#,
        #"{"type":"transcript-final","text":"Hello","providerMetadata":null}"#,
        #"{"type":"finish","text":"Hello","segments":[{"text":"Hello","endSecond":1}]}"#,
        #"{"type":"response-metadata","timestamp":"not-a-date"}"#,
        #"{"type":"raw"}"#,
        #"{"type":"error","error":null,"constructor":{"prototype":{"polluted":true}}}"#,
    ])
    func invalidServerPart(text: String) {
        #expect(parseTranscriptionStreamPart(text) == nil)
    }

    @Test("Timestamp nulls are revived as absent dates and non-JSON payloads are dropped")
    func nullableTimestampAndSerializationFailure() {
        #expect(parseTranscriptionStreamPart(#"{"type":"response-metadata","timestamp":null,"modelId":"model-1"}"#)
            == .responseMetadata(timestamp: nil, modelId: "model-1", headers: nil, body: nil))
        #expect(serializeTranscriptionStreamPart(.raw(rawValue: .number(.nan))) == nil)
    }
}
