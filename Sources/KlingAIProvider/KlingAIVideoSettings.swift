import Foundation

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/klingai/src/klingai-video-settings.ts
// Upstream commit: 73d5c59
//===----------------------------------------------------------------------===//

public struct KlingAIVideoModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}

public extension KlingAIVideoModelId {
    // Text-to-Video
    static let klingV1T2v: KlingAIVideoModelId = "kling-v1-t2v"
    static let klingV16T2v: KlingAIVideoModelId = "kling-v1.6-t2v"
    static let klingV2MasterT2v: KlingAIVideoModelId = "kling-v2-master-t2v"
    static let klingV21MasterT2v: KlingAIVideoModelId = "kling-v2.1-master-t2v"
    static let klingV25TurboT2v: KlingAIVideoModelId = "kling-v2.5-turbo-t2v"
    static let klingV26T2v: KlingAIVideoModelId = "kling-v2.6-t2v"
    static let klingV30T2v: KlingAIVideoModelId = "kling-v3.0-t2v"

    // Image-to-Video
    static let klingV1I2v: KlingAIVideoModelId = "kling-v1-i2v"
    static let klingV15I2v: KlingAIVideoModelId = "kling-v1.5-i2v"
    static let klingV16I2v: KlingAIVideoModelId = "kling-v1.6-i2v"
    static let klingV2MasterI2v: KlingAIVideoModelId = "kling-v2-master-i2v"
    static let klingV21I2v: KlingAIVideoModelId = "kling-v2.1-i2v"
    static let klingV21MasterI2v: KlingAIVideoModelId = "kling-v2.1-master-i2v"
    static let klingV25TurboI2v: KlingAIVideoModelId = "kling-v2.5-turbo-i2v"
    static let klingV26I2v: KlingAIVideoModelId = "kling-v2.6-i2v"
    static let klingV30I2v: KlingAIVideoModelId = "kling-v3.0-i2v"

    // Motion Control
    static let klingV26MotionControl: KlingAIVideoModelId = "kling-v2.6-motion-control"
}

