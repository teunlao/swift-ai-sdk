import Foundation

public struct ProdiaVideoModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, Codable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.init(rawValue: value) }
    public static let wan22LightningTxt2vid: Self = "inference.wan2-2.lightning.txt2vid.v0"
    public static let wan22LightningImg2vid: Self = "inference.wan2-2.lightning.img2vid.v0"
}
