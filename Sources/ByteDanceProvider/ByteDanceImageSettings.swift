import Foundation

public struct ByteDanceImageModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}

public extension ByteDanceImageModelId {
    static let dolaSeedream50Pro260628: ByteDanceImageModelId = "dola-seedream-5-0-pro-260628"
    static let seedream50260128: ByteDanceImageModelId = "seedream-5-0-260128"
    static let seedream50Lite260128: ByteDanceImageModelId = "seedream-5-0-lite-260128"
    static let seedream45251128: ByteDanceImageModelId = "seedream-4-5-251128"
    static let seedream40250828: ByteDanceImageModelId = "seedream-4-0-250828"
}
