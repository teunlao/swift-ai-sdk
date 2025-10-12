/**
 Warning from the model provider for transcription calls.

 Port of `@ai-sdk/provider/src/transcription-model/v2/transcription-model-v2-call-warning.ts`.

 The call will proceed, but some settings might not be supported, which can lead to
 suboptimal results.
 */
public enum TranscriptionModelV2CallWarning: Sendable, Equatable {
    /// A setting was provided that is not supported by the provider
    case unsupportedSetting(setting: String, details: String?)

    /// Other warning with a custom message
    case other(message: String)
}
