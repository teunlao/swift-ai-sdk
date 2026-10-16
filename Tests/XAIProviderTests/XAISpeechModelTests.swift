import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import XAIProvider

@Suite("XAISpeechModel")
struct XAISpeechModelTests {
    private func speech(_ data: Data, status: Int = 200, inspect: @escaping @Sendable (URLRequest) throws -> Void = { _ in }) -> XAISpeechModel {
        createXai(settings: .init(apiKey: "key", fetch: { request in
            try inspect(request)
            return FetchResponse(body: .data(data), urlResponse: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["X-Trace-Id": "trace", "Content-Type": "application/json"])!)
        })).speech()
    }

    @Test("default synthesis sends text, voice, language and MP3 codec")
    func binary() async throws {
        let model = speech(Data([1, 2, 3])) { request in
            #expect(request.url?.path == "/v1/tts")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer key")
            let body = try JSONDecoder().decode(JSONValue.self, from: request.httpBody!)
            #expect(body == .object(["text": .string("hello"), "voice_id": .string("eve"), "language": .string("auto"), "output_format": .object(["codec": .string("mp3")])]))
        }
        let result = try await model.doGenerate(options: .init(text: "hello"))
        #expect(result.audio == .binary(Data([1, 2, 3])))
        #expect(result.providerMetadata?["xai"]?["traceId"] == .string("trace"))
        #expect(result.warnings.isEmpty)
    }

    @Test("timestamp envelopes expose audio and character timing metadata")
    func timestamps() async throws {
        let payload = #"{"audio":"AQID","duration":0.5,"content_type":"audio/wav","audio_timestamps":{"graph_chars":["a"],"graph_times":[[0,0.5]]}}"#
        let model = speech(Data(payload.utf8)) { request in
            guard case .object(let body) = try JSONDecoder().decode(JSONValue.self, from: request.httpBody!) else { throw CancellationError() }
            #expect(body["voice_id"] == .string("rex"))
            #expect(body["language"] == .string("en"))
            #expect(body["speed"] == .number(1.1))
            #expect(body["output_format"] == .object(["codec": .string("wav"), "sample_rate": .number(24000)]))
            #expect(body["replace"] == .object(["AI": .string("ay eye")]))
            #expect(body["with_timestamps"] == .bool(true))
        }
        let result = try await model.doGenerate(options: .init(text: "a", voice: "rex", outputFormat: "wav", instructions: "whisper", speed: 1.1, language: "en", providerOptions: ["xai": ["sampleRate": .number(24000), "bitRate": .number(128000), "withTimestamps": .bool(true), "replace": .object(["AI": .string("ay eye")])]]))
        #expect(result.audio == .binary(Data([1, 2, 3])))
        #expect(result.providerMetadata?["xai"]?["duration"] == .number(0.5))
        #expect(result.providerMetadata?["xai"]?["contentType"] == .string("audio/wav"))
        #expect(result.providerMetadata?["xai"]?["audioTimestamps"] == .object(["graphChars": .array([.string("a")]), "graphTimes": .array([.array([.number(0), .number(0.5)])])]))
        #expect(result.warnings.count == 2)
    }

    @Test("invalid provider sampling options reject before HTTP")
    func invalidOptions() async throws {
        let model = speech(Data()) { _ in Issue.record("Invalid options must not send a request") }
        await #expect(throws: InvalidArgumentError.self) {
            _ = try await model.doGenerate(options: .init(text: "a", providerOptions: ["xai": ["sampleRate": .number(123)]]))
        }
    }

    @Test("speech API errors preserve the provider message")
    func errors() async throws {
        let model = speech(Data(#"{"error":"speed must be between 0.7 and 1.5"}"#.utf8), status: 400)
        do { _ = try await model.doGenerate(options: .init(text: "a")); Issue.record("Expected API error") }
        catch let error as APICallError {
            #expect(error.message == "speed must be between 0.7 and 1.5")
            #expect(error.statusCode == 400)
        }
    }
}
