import Foundation
import AISDKProvider
import AISDKProviderUtils

public protocol GeneratedAudioFile: GeneratedFile {
    var format: String { get }
}

public class DefaultGeneratedAudioFile: GeneratedAudioFile, @unchecked Sendable {
    private let file: DefaultGeneratedFile
    public let format: String
    public var mediaType: String { file.mediaType }
    public var data: Data { file.data }
    public var base64: String { file.base64 }
    public var providerMetadata: ProviderMetadata? { file.providerMetadata }

    private static func determineFormat(_ mediaType: String) throws -> String {
        let parts = mediaType.split(separator: "/", omittingEmptySubsequences: false)
        let format = !mediaType.isEmpty && parts.count == 2 && mediaType != "audio/mpeg" ? String(parts[1]) : "mp3"
        guard !format.isEmpty else {
            throw InvalidResponseDataError(data: mediaType, message: "Could not determine audio format from media type: \(mediaType)")
        }
        return format
    }

    public init(data: Data, mediaType: String, providerMetadata: ProviderMetadata? = nil) throws {
        self.format = try Self.determineFormat(mediaType)
        self.file = DefaultGeneratedFile(data: data, mediaType: mediaType, providerMetadata: providerMetadata)
    }

    public init(base64: String, mediaType: String, providerMetadata: ProviderMetadata? = nil) throws {
        self.format = try Self.determineFormat(mediaType)
        self.file = DefaultGeneratedFile(base64: base64, mediaType: mediaType, providerMetadata: providerMetadata)
    }
}

public final class DefaultGeneratedAudioFileWithType: DefaultGeneratedAudioFile, @unchecked Sendable {
    public let type = "audio"
}
