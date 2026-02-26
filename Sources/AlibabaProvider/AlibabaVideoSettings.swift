import Foundation

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/alibaba/src/alibaba-video-settings.ts
// Upstream commit: 73d5c59
//===----------------------------------------------------------------------===//

public struct AlibabaVideoModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}

public extension AlibabaVideoModelId {
    // Text-to-Video
    static let wan26T2v: AlibabaVideoModelId = "wan2.6-t2v"
    static let wan25T2vPreview: AlibabaVideoModelId = "wan2.5-t2v-preview"

    // Image-to-Video (first frame)
    static let wan26I2v: AlibabaVideoModelId = "wan2.6-i2v"
    static let wan26I2vFlash: AlibabaVideoModelId = "wan2.6-i2v-flash"

    // Reference-to-Video
    static let wan26R2v: AlibabaVideoModelId = "wan2.6-r2v"
    static let wan26R2vFlash: AlibabaVideoModelId = "wan2.6-r2v-flash"
}

