import Foundation

public struct GoogleImageSettings: Sendable, Equatable {
    public var maxImagesPerCall: Int?

    public init(maxImagesPerCall: Int? = nil) {
        self.maxImagesPerCall = maxImagesPerCall
    }
}
