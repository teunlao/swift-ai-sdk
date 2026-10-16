import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import GoogleVertexProvider

@Suite("Vertex transcription V4")
struct GoogleVertexTranscriptionTests {
    @Test(arguments: ["googleVertex", "vertex", "google"])
    func cloudSpeechRequestAndResponse(namespace: String) async throws {
        let requests = VertexRequests()
        let provider = createGoogleVertex(settings: .init(location: "global", project: "project", fetch: { request in
            await requests.append(request)
            return try vertexResponse(request, #"{"results":[{"alternatives":[{"transcript":"Hello","words":[{"word":"Hello","startOffset":"0s","endOffset":"0.75s"},{"word":"invalid","startOffset":"bad","endOffset":"1s"}]}],"languageCode":"en-US"},{"alternatives":[{"transcript":"world","words":[{"word":"world","startOffset":"0.75s","endOffset":"1.5s"}]}]}],"metadata":{"totalBilledDuration":"2.400s"}}"#)
        }, accessTokenProvider: { "token" }))
        let result = try await provider.transcription(modelId: "chirp_3").doGenerate(options: .init(
            audio: .binary(Data([1, 2, 3])), mediaType: "audio/wav",
            providerOptions: [namespace: ["region": .string("us"), "languageCodes": .array([.string("en-US")]), "enableAutomaticPunctuation": .bool(false)]]
        ))
        #expect(result.text == "Hello world")
        #expect(result.language == "en")
        #expect(result.segments == [.init(text: "Hello", startSecond: 0, endSecond: 0.75), .init(text: "world", startSecond: 0.75, endSecond: 1.5)])
        #expect(result.durationInSeconds == 2.4)
        #expect(result.response.headers?["x-request-id"] == "vertex-request")
        let request = try #require(await requests.last)
        #expect(request.url?.absoluteString == "https://us-speech.googleapis.com/v2/projects/project/locations/us/recognizers/_:recognize")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token")
        #expect(try vertexBody(request) == .object([
            "config": .object([
                "model": .string("chirp_3"), "languageCodes": .array([.string("en-US")]), "autoDecodingConfig": .object([:]),
                "features": .object(["enableWordTimeOffsets": .bool(true), "enableAutomaticPunctuation": .bool(false)])
            ]), "content": .string("AQID")
        ]))
    }

    @Test func geminiUnaryMapsTranscriptAndUsage() async throws {
        let requests = VertexRequests()
        let model = vertexProvider { request in
            await requests.append(request)
            return try vertexResponse(request, #"{"candidates":[{"content":{"parts":[{"audioTranscription":{"text":"spoken words","languageCode":"fr-FR","words":[{"word":"spoken","startOffset":"1s","endOffset":"1.2s"}]}},{"text":"Formatted transcript"}]}}],"usageMetadata":{"promptTokenCount":10,"totalTokenCount":12}}"#)
        }.transcription(modelId: "gemini-3.5-transcribe")
        let result = try await model.doGenerate(options: .init(audio: .base64("AQID"), mediaType: "audio/wav", providerOptions: [
            "googleVertex": ["languageCodes": .array([.string("fr-FR")]), "customVocabulary": .array([.string("Vertex")]), "wordTimestamp": .bool(true), "diarization": .bool(true), "mode": .string("SMART")],
            "vertex": ["mode": .string("VERBATIM")]
        ]))
        #expect(result.text == "Formatted transcript")
        #expect(result.language == "fr-FR")
        #expect(result.segments == [.init(text: "spoken", startSecond: 1, endSecond: 1.2)])
        #expect(result.usage?["totalTokenCount"] == .number(12))
        #expect(result.providerMetadata?["google"]?["usageMetadata"] == result.usage.map(JSONValue.object))
        let request = try #require(await requests.last)
        #expect(request.url?.absoluteString == "https://vertex.example/models/gemini-3.5-transcribe:generateContent")
        #expect(try vertexBody(request) == .object([
            "contents": .array([.object(["role": .string("user"), "parts": .array([.object(["inlineData": .object(["mimeType": .string("audio/wav"), "data": .string("AQID")])])])])]),
            "generationConfig": .object(["audioTranscriptionConfig": .object([
                "languageCodes": .array([.string("fr-FR")]), "customVocabulary": .array([.string("Vertex")]),
                "wordTimestamp": .bool(true), "diarization": .bool(true), "mode": .string("SMART")
            ])])
        ]))
    }

    @Test func invalidRegionAndNullOptions() async throws {
        let provider = createGoogleVertex(settings: .init(location: "global", project: "project", fetch: { _ in throw CancellationError() }, accessTokenProvider: { "token" }))
        let model = provider.transcription(modelId: "chirp_3")
        for region in ["evil.example/#", "us\n"] {
            await #expect(throws: InvalidArgumentError.self) { _ = try await model.doGenerate(options: .init(audio: .base64("AQID"), mediaType: "audio/wav", providerOptions: ["googleVertex": ["region": .string(region)]])) }
        }
        await #expect(throws: InvalidArgumentError.self) { _ = try await model.doGenerate(options: .init(audio: .base64("AQID"), mediaType: "audio/wav", providerOptions: ["googleVertex": ["languageCodes": .null]])) }
    }

    @Test func rejectsExpressTranscriptionAndUnaryLiveModel() async throws {
        let provider = createGoogleVertex(settings: .init(apiKey: "key", fetch: { _ in throw CancellationError() }))
        await #expect(throws: InvalidArgumentError.self) { _ = try await provider.transcription(modelId: "chirp_3").doGenerate(options: .init(audio: .base64("AQID"), mediaType: "audio/wav")) }
        let live = vertexProvider { _ in throw CancellationError() }.transcription(modelId: "gemini-3.5-transcribe-live")
        await #expect(throws: InvalidArgumentError.self) { _ = try await live.doGenerate(options: .init(audio: .base64("AQID"), mediaType: "audio/wav")) }
    }
}
