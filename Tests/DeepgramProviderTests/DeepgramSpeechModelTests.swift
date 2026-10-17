import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import DeepgramProvider

@Suite("Deepgram speech public contracts")
struct DeepgramSpeechModelTests {
    @Test("voice families compose voice/language, accept speed and preserve header usage metadata")
    func voiceFamily() async throws {
        let bytes = Data([1, 2, 3])
        let endpoint = AudioEndpoint(audio: bytes, headers: ["dg-char-count": "0x20", "dg-breaks-applied": "1.5", "dg-pronunciations-applied": "invalid", "dg-additional-model-uuids": "a, b,", "dg-model-name": "aura", "dg-project-id": "private", "dg-request-id": "req"])
        let result = try await createDeepgram(settings: .init(apiKey: "key", fetch: { await endpoint.fetch($0) })).speech(modelId: .aura2).doGenerate(options: .init(text: "Hello", voice: "\u{FEFF}thalia ", speed: 1.25, language: "auto"))
        #expect(result.audio == .binary(bytes))
        #expect(result.usage == ["characters": 32])
        #expect(result.providerMetadata == ["deepgram": ["modelName": "aura", "requestId": "req", "charCount": 32, "breaksApplied": 1.5, "additionalModelUuids": ["a", " b", ""]]])
        #expect(try await endpoint.query() == ["model": "aura-2-thalia-en", "encoding": "mp3", "speed": "1.25"])
        #expect(result.warnings.contains { if case .compatibility(let feature, _) = $0 { feature == "language" } else { false } })
        #expect(try JSONDecoder().decode(JSONValue.self, from: #require(try await endpoint.sent().httpBody)) == ["text": "Hello"])
    }

    @Test("full IDs remain unchanged while options override output encoding and retain valid bitrate")
    func optionPrecedence() async throws {
        let endpoint = AudioEndpoint(audio: Data())
        let result = try await createDeepgram(settings: .init(apiKey: "key", fetch: { await endpoint.fetch($0) })).speech(modelId: "aura-2-helena-en").doGenerate(options: .init(
            text: "Hello", voice: "ignored", outputFormat: "linear16_24000", instructions: "tone", language: "fr", providerOptions: ["deepgram": ["encoding": "mp3", "bitRate": "0xBB80", "sampleRate": 48000, "container": "wav", "tag": ["a", "b"], "mipOptOut": false]]))
        #expect(try await endpoint.query() == ["model": "aura-2-helena-en", "encoding": "mp3", "bit_rate": "0xBB80", "tag": "a,b", "mip_opt_out": "false"])
        let features = result.warnings.compactMap { if case .unsupported(let feature, _) = $0 { feature } else { nil } }
        #expect(features == ["providerOptions", "providerOptions", "voice", "language", "instructions"])
        #expect(result.providerMetadata == ["deepgram": [:]])
    }

    @Test("format suffixes follow parseInt and source NaN bitrate comparisons", arguments: ["wav_44100Hz", "opus"])
    func formatAndBitrate(format: String) async throws {
        let endpoint = AudioEndpoint(audio: Data())
        let result = try await createDeepgram(settings: .init(apiKey: "key", fetch: { await endpoint.fetch($0) })).speech(modelId: "aura-full-en").doGenerate(options: .init(text: "Hello", outputFormat: format, providerOptions: format == "opus" ? ["deepgram": ["bitRate": "auto"]] : nil))
        if format == "opus" {
            #expect(try await endpoint.query()["bit_rate"] == "auto")
            #expect(try await endpoint.query()["container"] == "ogg")
        } else {
            #expect(try await endpoint.query()["sample_rate"] == "44100")
            #expect(try await endpoint.query()["encoding"] == "linear16")
        }
        #expect(result.warnings.isEmpty)
    }

    @Test("provider options validate callback and known value types")
    func invalidOptions() async throws {
        let endpoint = AudioEndpoint(audio: Data())
        let model = createDeepgram(settings: .init(apiKey: "key", fetch: { await endpoint.fetch($0) })).speech(modelId: "aura-full-en")
        await #expect(throws: InvalidArgumentError.self) { try await model.doGenerate(options: .init(text: "Hello", providerOptions: ["deepgram": ["callback": "not a url"]])) }
        await #expect(throws: InvalidArgumentError.self) { try await model.doGenerate(options: .init(text: "Hello", providerOptions: ["deepgram": ["sampleRate": "48000"]])) }
    }

    @Test("cancellation surfaces from the public speech operation")
    func cancellation() async throws {
        let endpoint = AudioEndpoint(audio: Data())
        let model = createDeepgram(settings: .init(apiKey: "key", fetch: { await endpoint.fetch($0) })).speech(modelId: "full")
        await #expect(throws: CancellationError.self) { try await model.doGenerate(options: .init(text: "Hello", abortSignal: { true })) }
    }
}
