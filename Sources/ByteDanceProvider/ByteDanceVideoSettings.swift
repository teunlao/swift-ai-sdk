import Foundation

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/bytedance/src/bytedance-video-settings.ts
// Upstream commit: 73d5c59
//===----------------------------------------------------------------------===//

public struct ByteDanceVideoModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}

public extension ByteDanceVideoModelId {
    static let seedance15Pro251215: ByteDanceVideoModelId = "seedance-1-5-pro-251215"
    static let seedance10Pro250528: ByteDanceVideoModelId = "seedance-1-0-pro-250528"
    static let seedance10ProFast251015: ByteDanceVideoModelId = "seedance-1-0-pro-fast-251015"
    static let seedance10LiteT2v250428: ByteDanceVideoModelId = "seedance-1-0-lite-t2v-250428"
    static let seedance10LiteI2v250428: ByteDanceVideoModelId = "seedance-1-0-lite-i2v-250428"
}

