import Foundation

public struct GoogleGenerativeAIImageSettings: Sendable, Equatable {
    public var maxImagesPerCall: Int?

    public init(maxImagesPerCall: Int? = nil) {
        self.maxImagesPerCall = maxImagesPerCall
    }
}
