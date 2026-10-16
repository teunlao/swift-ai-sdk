import AISDKProvider

public func getGoogleSpeechInput(text: String, voice: String? = nil, providerOptions: SharedV4ProviderOptions? = nil) -> (text: String, usesCustomVoice: Bool) {
    let google = providerOptions?["google"]
    var transcript = text
    if case .array(let turns) = google?["turns"], !turns.isEmpty {
        let texts = turns.compactMap { value -> String? in
            guard case .object(let turn) = value, case .string(let text) = turn["text"] else { return nil }
            return text
        }
        if texts.count == turns.count { transcript = texts.joined() }
    }
    var custom = voice?.hasPrefix("voice_") == true || voice?.hasPrefix("voicekey_") == true
    if case .object(let multi) = google?["multiSpeakerVoiceConfig"], case .array(let speakers) = multi["speakerVoiceConfigs"] {
        custom = custom || speakers.contains { value in
            guard case .object(let speaker) = value, case .object(let config) = speaker["voiceConfig"] else { return false }
            return config["voice"] != nil
        }
    }
    return (transcript, custom)
}
