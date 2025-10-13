import Foundation

/**
 A generated file.

 Port of `@ai-sdk/ai/src/generate-text/generated-file.ts`.
 */

/// Protocol for a generated file.
public protocol GeneratedFile: Sendable {
    /// File as a base64 encoded string.
    var base64: String { get }

    /// File as a Data object (Swift equivalent of Uint8Array).
    var data: Data { get }

    /// The IANA media type of the file.
    ///
    /// See https://www.iana.org/assignments/media-types/media-types.xhtml
    var mediaType: String { get }
}

/// Default implementation of GeneratedFile with lazy conversion between base64 and Data.
public class DefaultGeneratedFile: GeneratedFile, @unchecked Sendable {
    private var base64Data: String?
    private var binaryData: Data?
    private let lock = NSLock()

    public let mediaType: String

    public init(data: Data, mediaType: String) {
        self.binaryData = data
        self.mediaType = mediaType
    }

    public init(base64: String, mediaType: String) {
        self.base64Data = base64
        self.mediaType = mediaType
    }

    /// Lazy conversion with caching to avoid unnecessary conversion overhead.
    public var base64: String {
        lock.lock()
        defer { lock.unlock() }

        if let base64Data = base64Data {
            return base64Data
        }

        // Convert from Data to base64
        let base64String = binaryData!.base64EncodedString()
        base64Data = base64String
        return base64String
    }

    /// Lazy conversion with caching to avoid unnecessary conversion overhead.
    public var data: Data {
        lock.lock()
        defer { lock.unlock() }

        if let binaryData = binaryData {
            return binaryData
        }

        // Convert from base64 to Data
        let data = Data(base64Encoded: base64Data!)!
        binaryData = data
        return data
    }
}

/// Default generated file with type discriminator.
public final class DefaultGeneratedFileWithType: DefaultGeneratedFile, @unchecked Sendable {
    public let type: String = "file"

    public override init(data: Data, mediaType: String) {
        super.init(data: data, mediaType: mediaType)
    }

    public override init(base64: String, mediaType: String) {
        super.init(base64: base64, mediaType: mediaType)
    }
}
