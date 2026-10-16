import Foundation
import Testing
import AISDKProvider
import GoogleProvider

@Suite("Google Gemini speech V4")
struct GoogleSpeechTests {
    @Test("older TTS wraps PCM in WAV using the reported sample rate")
    func pcmWav() async throws {
        let transport = GoogleTransport([.init(try googleFixture("speech-pcm.json"))])
        let model = await transport.provider().speech(modelId: "gemini-2.5-flash-preview-tts")
        let result = try await model.doGenerate(options: .init(text: "Hello", instructions: "Whisper"))
        guard case .binary(let audio) = result.audio else { Issue.record("expected binary audio"); return }
        #expect(audio.count == 48)
        #expect(String(decoding: audio.prefix(4), as: UTF8.self) == "RIFF")
        #expect(Array(audio[24..<28]) == [0x80, 0x3e, 0, 0])
        #expect(audio.suffix(4) == Data([1, 2, 3, 4]))
        #expect(result.providerMetadata?["google"]?["sampleRate"] == .number(16000))
        #expect(result.usage?["candidatesTokenCount"] == .number(4))
        let request = try #require(await transport.captured().first)
        let body = try googleBody(request)
        #expect(object(array(object(array(body["contents"]).first)["parts"]).first)["text"] == .string("Whisper: Hello"))
    }

    @Test("Gemini 3.8 sends structured turns and preserves native WAV bytes")
    func structuredSpeech() async throws {
        let transport = GoogleTransport([.init(try googleFixture("speech-wav.json"))])
        let model = await transport.provider().speech(modelId: "gemini-3.8-flash-tts")
        let speaker: JSONValue = .object(["speakerVoiceConfigs": .array([.object(["speaker": .string("A"), "voiceConfig": .object(["prebuiltVoiceConfig": .object(["voiceName": .string("Kore")])])])])])
        let result = try await model.doGenerate(options: .init(text: "", outputFormat: "audio/wav", instructions: "default style", providerOptions: ["google": ["turns": .array([.object(["text": .string("Hello"), "speechMetadata": .object(["speaker": .string("A"), "style": .string("cheerful")])])]), "multiSpeakerVoiceConfig": speaker]]))
        #expect(result.audio == .binary(Data("RIFF".utf8)))
        let request = try #require(await transport.captured().first)
        let body = try googleBody(request)
        let part = object(array(object(array(body["contents"]).first)["parts"]).first)
        #expect(part["speechMetadata"] == .object(["speaker": .string("A"), "style": .string("cheerful")]))
        #expect(object(body["generationConfig"])["responseFormat"] == .object(["audio": .object(["mimeType": .string("AUDIO_WAV")])]))
    }

    @Test("speech rejects custom voices and invalid multi-speaker turns")
    func invalidSpeech() async throws {
        let model = createGoogle(settings: .init(apiKey: "key")).speech(modelId: "gemini-3.8-flash-tts")
        await #expect(throws: InvalidArgumentError.self) { try await model.doGenerate(options: .init(text: "Hello", voice: "voice_custom")) }
        await #expect(throws: InvalidArgumentError.self) { try await model.doGenerate(options: .init(text: "Hello", providerOptions: ["google": ["multiSpeakerVoiceConfig": .object(["speakerVoiceConfigs": .array([])])]])) }
    }
}
