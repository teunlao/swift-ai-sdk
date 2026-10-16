import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import GoogleVertexProvider

@Suite("Vertex speech V4")
struct GoogleVertexSpeechTests {
    @Test(arguments: [(nil as String?, nil as String?, "en-US", "en-US-Chirp3-HD-Kore"), ("fr-FR-Chirp3-HD-Aoede", nil, "fr-FR", "fr-FR-Chirp3-HD-Aoede"), ("Chirp3-HD-Kore", "de-DE", "de-DE", "Chirp3-HD-Kore")])
    func chirpVoice(voice: String?, language: String?, expectedLanguage: String, expectedVoice: String) async throws {
        let requests = VertexRequests()
        let provider = createGoogleVertex(settings: .init(fetch: { request in
            await requests.append(request)
            return try vertexResponse(request, #"{"audioContent":"AQID"}"#)
        }, baseURL: "https://vertex.example", accessTokenProvider: { "speech-token" }))
        let result = try await provider.speech(modelId: "chirp-3-hd").doGenerate(options: .init(
            text: "hello", voice: voice, outputFormat: "mp3", instructions: "quietly", speed: 1.2, language: language
        ))
        #expect(result.audio == .binary(Data([1, 2, 3])))
        #expect(result.providerMetadata?["google"]?["mimeType"] == .string("audio/wav"))
        #expect(result.warnings.count == 2)
        #expect(result.response.headers?["x-request-id"] == "vertex-request")
        let request = try #require(await requests.last)
        #expect(request.url?.absoluteString == "https://texttospeech.googleapis.com/v1/text:synthesize")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer speech-token")
        #expect(try vertexBody(request) == .object([
            "input": .object(["text": .string("hello")]),
            "voice": .object(["languageCode": .string(expectedLanguage), "name": .string(expectedVoice)]),
            "audioConfig": .object(["audioEncoding": .string("LINEAR16"), "speakingRate": .number(1.2)])
        ]))
        #expect(try jsonValue(from: JSONSerialization.jsonObject(with: Data((result.request?.body as? String ?? "").utf8))) == vertexBody(request))
    }

    @Test func geminiSpeechUsesVertexEndpoint() async throws {
        let requests = VertexRequests()
        let provider = vertexProvider { request in
            await requests.append(request)
            return try vertexResponse(request, #"{"candidates":[{"content":{"parts":[{"inlineData":{"mimeType":"audio/L16;codec=pcm;rate=24000","data":"AQID"}}]}}]}"#)
        }
        let result = try await provider.speech(modelId: "gemini-2.5-flash-tts").doGenerate(options: .init(text: "hello"))
        guard case .binary(let audio) = result.audio else { Issue.record("Expected audio"); return }
        #expect(!audio.isEmpty)
        #expect(await requests.last?.url?.absoluteString == "https://vertex.example/models/gemini-2.5-flash-tts:generateContent")
    }

    @Test func chirpRejectsExpressMode() async throws {
        let provider = createGoogleVertex(settings: .init(apiKey: "key", fetch: { _ in throw CancellationError() }))
        await #expect(throws: InvalidArgumentError.self) { _ = try await provider.speech(modelId: "chirp-3-hd").doGenerate(options: .init(text: "hello")) }
    }
}
