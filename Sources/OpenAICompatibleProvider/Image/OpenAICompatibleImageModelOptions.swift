import Foundation

public struct OpenAICompatibleImageModelOptions: Codable, Sendable, Equatable {
    public var size: String?
    public var quality: String?
    public var output_format: String?
    public var output_compression: Double?
    public var background: String?

    public init(size: String? = nil, quality: String? = nil, output_format: String? = nil,
                output_compression: Double? = nil, background: String? = nil) {
        self.size = size; self.quality = quality; self.output_format = output_format
        self.output_compression = output_compression; self.background = background
    }
}
