import Foundation

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/alibaba/src/alibaba-video-settings.ts
// Upstream commit: 8a5233b15b1e69573d63faee6cd0014559252ee4
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
    static let wan27T2v: AlibabaVideoModelId = "wan2.7-t2v"
    static let wan27T2v20260612: AlibabaVideoModelId = "wan2.7-t2v-2026-06-12"

    // Image-to-Video (first frame)
    static let wan26I2v: AlibabaVideoModelId = "wan2.6-i2v"
    static let wan26I2vFlash: AlibabaVideoModelId = "wan2.6-i2v-flash"

    // Reference-to-Video
    static let wan26R2v: AlibabaVideoModelId = "wan2.6-r2v"
    static let wan26R2vFlash: AlibabaVideoModelId = "wan2.6-r2v-flash"
    static let wan27R2v: AlibabaVideoModelId = "wan2.7-r2v"
    static let wan27R2v20260612: AlibabaVideoModelId = "wan2.7-r2v-2026-06-12"
    static let wan30Video: AlibabaVideoModelId = "wan3.0-video"
}

