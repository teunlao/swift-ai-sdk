import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 A generated audio file.

 Port of `@ai-sdk/ai/src/generate-speech/generated-audio-file.ts`.
 */

/// Protocol for generated audio files returned by `generateSpeech`.
public protocol GeneratedAudioFile: GeneratedFile {
    /// Audio format of the file (e.g., "mp3", "wav").
    var format: String { get }
}

/// Default generated audio file implementation.
public class DefaultGeneratedAudioFile: DefaultGeneratedFile, GeneratedAudioFile, @unchecked Sendable {
    private static let defaultFormat = "mp3"
    private static let formatErrorMessage =
        "Audio format must be provided or determinable from media type"

    public let format: String

    private static func determineFormat(mediaType: String) -> String {
        guard !mediaType.isEmpty else {
            return defaultFormat
        }

        let components = mediaType.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count == 2 else {
            return defaultFormat
        }

        // Preserve mp3 for historical compatibility when media type is audio/mpeg.
        if mediaType == "audio/mpeg" {
            return defaultFormat
        }

        return String(components[1])
    }

    private static func validateFormat(_ format: String) {
        precondition(!format.isEmpty, formatErrorMessage)
    }

    public override init(data: Data, mediaType: String) {
        let resolvedFormat = Self.determineFormat(mediaType: mediaType)
        Self.validateFormat(resolvedFormat)
        self.format = resolvedFormat
        super.init(data: data, mediaType: mediaType)
    }

    public override init(base64: String, mediaType: String) {
        let resolvedFormat = Self.determineFormat(mediaType: mediaType)
        Self.validateFormat(resolvedFormat)
        self.format = resolvedFormat
        super.init(base64: base64, mediaType: mediaType)
    }
}

/// Default generated audio file with `type` discriminator.
public final class DefaultGeneratedAudioFileWithType: DefaultGeneratedAudioFile, @unchecked Sendable {
    public let type = "audio"

    public override init(data: Data, mediaType: String) {
        super.init(data: data, mediaType: mediaType)
    }

    public override init(base64: String, mediaType: String) {
        super.init(base64: base64, mediaType: mediaType)
    }
}
