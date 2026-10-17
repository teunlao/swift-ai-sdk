import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
@testable import GroqProvider

@Suite("GroqTranscriptionModel")
struct GroqTranscriptionModelTests {
    private static let verboseResponse = #"{"task":"transcribe","language":"English","duration":2.5,"text":"Hello world!","segments":[{"id":0,"seek":0,"start":0,"end":2.48,"text":"Hello world!","tokens":[50365,2425,490,264],"temperature":0,"avg_logprob":-0.29,"compression_ratio":0.78,"no_speech_prob":0.03}],"x_groq":{"id":"request-1"},"extra":"raw"}"#

    private func model(
        data: Data? = nil,
        status: Int = 200,
        contentType: String = "application/json",
        inspect: @escaping @Sendable (URLRequest) throws -> Void = { _ in }
    ) -> GroqTranscriptionModel {
        let responseData = data ?? Data(Self.verboseResponse.utf8)
        return GroqTranscriptionModel(modelId: .whisperLargeV3Turbo, config: .init(
            provider: "groq.transcription",
            url: { options in "https://api.groq.com/openai/v1\(options.path)" },
            headers: { ["Authorization": "Bearer test"] },
            fetch: { request in
                try inspect(request)
                return FetchResponse(body: .data(responseData), urlResponse: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": contentType, "X-Request-Id": "request-1"])!)
            },
            currentDate: { Date(timeIntervalSince1970: 0) }
        ))
    }

    private func fieldValues(_ name: String, request: URLRequest) throws -> [String] {
        let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
        let pattern = "name=\"\(NSRegularExpression.escapedPattern(for: name))\"\r\n\r\n(.*?)\r\n"
        let regex = try NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators)
        let string = body as NSString
        return regex.matches(in: body, range: NSRange(location: 0, length: string.length)).map { string.substring(with: $0.range(at: 1)) }
    }

    @Test("binary and base64 audio preserve bytes and media-derived filenames", arguments: [false, true])
    func audioUpload(base64: Bool) async throws {
        let audio = Data([0, 1, 2, 255])
        let mediaType = base64 ? "audio/mp4" : "audio/wav"
        let filename = base64 ? "audio.m4a" : "audio.wav"
        _ = try await model { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.absoluteString == "https://api.groq.com/openai/v1/audio/transcriptions")
            #expect(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
            let values = try fieldValues("model", request: request)
            #expect(values == ["whisper-large-v3-turbo"])
            var expected = Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\nContent-Type: \(mediaType)\r\n\r\n".utf8)
            expected.append(audio)
            expected.append(Data("\r\n".utf8))
            let body = try #require(request.httpBody)
            #expect(body.range(of: expected) != nil)
        }.doGenerate(options: .init(audio: base64 ? .base64(audio.base64EncodedString()) : .binary(audio), mediaType: mediaType))
    }

    @Test("verbose responses expose text, segments, language, duration and raw metadata")
    func responseMapping() async throws {
        let result = try await model().doGenerate(options: .init(audio: .binary(Data([1])), mediaType: "audio/wav"))
        #expect(result.text == "Hello world!")
        #expect(result.segments == [.init(text: "Hello world!", startSecond: 0, endSecond: 2.48)])
        #expect(result.language == "English")
        #expect(result.durationInSeconds == 2.5)
        #expect(result.warnings.isEmpty)
        #expect(result.response.timestamp == Date(timeIntervalSince1970: 0))
        #expect(result.response.modelId == "whisper-large-v3-turbo")
        #expect(result.response.headers?["x-request-id"] == "request-1")
        let raw = try jsonValue(from: #require(result.response.body))
        let expected = try JSONDecoder().decode(JSONValue.self, from: Data(Self.verboseResponse.utf8))
        #expect(raw == expected)
    }

    @Test("provider options become scalar and repeated array multipart fields", arguments: [0.0, 0.5, 1.0])
    func providerOptions(temperature: Double) async throws {
        _ = try await model { request in
            let language = try fieldValues("language", request: request)
            let prompt = try fieldValues("prompt", request: request)
            let format = try fieldValues("response_format", request: request)
            let temperatureValues = try fieldValues("temperature", request: request)
            let granularities = try fieldValues("timestamp_granularities[]", request: request)
            #expect(language == ["en"])
            #expect(prompt == ["Context"])
            #expect(format == ["verbose_json"])
            #expect(temperatureValues == [temperature == 0 ? "0" : temperature == 1 ? "1" : "0.5"])
            #expect(granularities == ["segment", "word"])
        }.doGenerate(options: .init(audio: .binary(Data([1])), mediaType: "audio/wav", providerOptions: ["groq": ["language": "en", "prompt": "Context", "responseFormat": "verbose_json", "temperature": .number(temperature), "timestampGranularities": ["segment", "word"]]]))
    }

    @Test("nullish provider options are omitted and empty granularities are accepted", arguments: [false, true])
    func nullishOptions(emptyArray: Bool) async throws {
        let options: JSONObject = ["language": .null, "prompt": .null, "responseFormat": .null, "temperature": .null, "timestampGranularities": emptyArray ? .array([]) : .null]
        let result = try await model { request in
            for name in ["language", "prompt", "response_format", "temperature", "timestamp_granularities[]"] {
                let values = try fieldValues(name, request: request)
                #expect(values.isEmpty)
            }
        }.doGenerate(options: .init(audio: .binary(Data([1])), mediaType: "audio/wav", providerOptions: ["groq": options]))
        #expect(result.text == "Hello world!")
    }

    @Test("invalid temperatures and option types are rejected as invalid arguments", arguments: [
        ["temperature": JSONValue.number(-0.1)], ["temperature": .number(1.1)], ["temperature": .string("0.5")],
        ["timestampGranularities": .array([.number(1)])], ["responseFormat": .bool(true)]
    ])
    func invalidOptions(options: JSONObject) async throws {
        await #expect(throws: InvalidArgumentError.self) {
            _ = try await model().doGenerate(options: .init(audio: .binary(Data([1])), mediaType: "audio/wav", providerOptions: ["groq": options]))
        }
    }

    @Test("text format decodes raw UTF-8 with TextDecoder semantics")
    func plainText() async throws {
        var bytes = Data([0xEF, 0xBB, 0xBF])
        bytes.append(Data("Hello world!\n".utf8))
        bytes.append(0xFF)
        let result = try await model(data: bytes, contentType: "text/plain") { request in
            let format = try fieldValues("response_format", request: request)
            #expect(format == ["text"])
        }.doGenerate(options: .init(audio: .binary(Data([1])), mediaType: "audio/wav", providerOptions: ["groq": ["responseFormat": "text"]]))
        #expect(result.text == "Hello world!\n\u{FFFD}")
        #expect(result.response.body as? String == result.text)
        #expect(result.segments.isEmpty)
        #expect(result.language == nil)
        #expect(result.durationInSeconds == nil)
    }

    @Test("words are used only when segments are absent or null", arguments: [false, true])
    func wordsFallback(emptySegments: Bool) async throws {
        let payload: JSONValue = [
            "text": "Hello world", "x_groq": ["id": "request-1"], "language": "", "duration": .null,
            "segments": emptySegments ? .array([]) : .null,
            "words": [["word": "Hello", "start": 0, "end": 1], ["word": "world", "start": 1, "end": 2]]
        ]
        let result = try await model(data: JSONEncoder().encode(payload)).doGenerate(options: .init(audio: .binary(Data([1])), mediaType: "audio/wav"))
        #expect(result.segments == (emptySegments ? [] : [.init(text: "Hello", startSecond: 0, endSecond: 1), .init(text: "world", startSecond: 1, endSecond: 2)]))
        #expect(result.language == "")
        #expect(result.durationInSeconds == nil)
    }

    @Test("minimal JSON responses return an empty segment list")
    func minimalResponse() async throws {
        let result = try await model(data: Data(#"{"text":"Hello","x_groq":{"id":"request-1"}}"#.utf8)).doGenerate(options: .init(audio: .binary(Data([1])), mediaType: "audio/wav"))
        #expect(result.text == "Hello")
        #expect(result.segments.isEmpty)
        #expect(result.language == nil)
    }

    @Test("malformed JSON response fields reject at the HTTP boundary", arguments: [
        #"{"text":"Hello"}"#,
        #"{"text":"Hello","x_groq":{"id":1}}"#,
        #"{"text":"Hello","x_groq":{"id":"req"},"segments":[{"text":"Hello","start":0,"end":1}]}"#,
        #"{"text":"Hello","x_groq":{"id":"req"},"words":[{"word":"Hello","start":"0","end":1}]}"#,
        #"{"text":"Hello","x_groq":{"id":"req"},"task":1}"#
    ])
    func invalidResponse(payload: String) async throws {
        do {
            _ = try await model(data: Data(payload.utf8)).doGenerate(options: .init(audio: .binary(Data([1])), mediaType: "audio/wav"))
            Issue.record("Expected response validation failure")
        } catch let error as APICallError {
            #expect(error.message == "Invalid JSON response")
            #expect(error.statusCode == 200)
        }
    }

    @Test("API failures preserve the provider message and native request values")
    func apiError() async throws {
        let data = Data(#"{"error":{"message":"Unsupported audio","type":"invalid_request_error"}}"#.utf8)
        do {
            _ = try await model(data: data, status: 400).doGenerate(options: .init(audio: .binary(Data([1])), mediaType: "audio/wav", providerOptions: ["groq": ["timestampGranularities": ["segment", "word"]]]))
            Issue.record("Expected API error")
        } catch let error as APICallError {
            #expect(error.message == "Unsupported audio")
            #expect(error.statusCode == 400)
            let values = try #require(error.requestBodyValues as? [String: Any])
            #expect(values["model"] as? String == "whisper-large-v3-turbo")
            #expect(values["file"] as? Data == Data([1]))
            #expect(values["timestamp_granularities[]"] as? String == "word")
        }
    }

    @Test("aborted transcription returns cancellation before HTTP")
    func cancellation() async throws {
        await #expect(throws: CancellationError.self) {
            _ = try await model().doGenerate(options: .init(audio: .binary(Data([1])), mediaType: "audio/wav", abortSignal: { true }))
        }
    }

    @Test("provider transcription uses per-request auth, custom URLs, merged headers and Groq UA")
    func providerHeaders() async throws {
        let provider = createGroq(settings: .init(
            baseURL: "https://custom.groq.example/v2/", apiKey: "test-api-key",
            headers: ["X-Provider": "provider", "Override": "provider"], fetch: { request in
                #expect(request.url?.absoluteString == "https://custom.groq.example/v2/audio/transcriptions")
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-api-key")
                #expect(request.value(forHTTPHeaderField: "X-Provider") == "provider")
                #expect(request.value(forHTTPHeaderField: "X-Request") == "request")
                #expect(request.value(forHTTPHeaderField: "Override") == "request")
                #expect(request.value(forHTTPHeaderField: "User-Agent")?.contains("ai-sdk-groq/") == true)
                return FetchResponse(body: .data(Data(Self.verboseResponse.utf8)), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
            }
        ))
        let result = try await provider.transcription(modelId: .whisperLargeV3).doGenerate(options: .init(audio: .binary(Data([1])), mediaType: "audio/wav", headers: ["X-Request": "request", "Override": "request"]))
        #expect(result.text == "Hello world!")
        #expect(result.response.modelId == "whisper-large-v3")
    }
}
