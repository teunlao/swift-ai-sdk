/**
 Warning from the model provider for this call.

 Port of `@ai-sdk/provider/src/image-model/v2/image-model-v2-call-warning.ts`.

 The call will proceed, but e.g. some settings might not be supported,
 which can lead to suboptimal results.
 */
public enum ImageModelV2CallWarning: Sendable, Equatable {
    /// Unsupported setting warning
    case unsupportedSetting(setting: String, details: String?)

    /// Other warning type
    case other(message: String)
}
