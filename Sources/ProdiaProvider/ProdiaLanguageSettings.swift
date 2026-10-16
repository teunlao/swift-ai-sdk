import Foundation

public struct ProdiaLanguageModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, Codable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.init(rawValue: value) }
    public static let nanoBananaImg2imgV2: Self = "inference.nano-banana.img2img.v2"
}
