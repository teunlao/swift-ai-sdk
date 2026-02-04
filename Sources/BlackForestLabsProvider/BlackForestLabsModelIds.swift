import Foundation

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/black-forest-labs/src/black-forest-labs-image-settings.ts
// Upstream commit: f3a72bc2a
//===----------------------------------------------------------------------===//

public struct BlackForestLabsImageModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}

public extension BlackForestLabsImageModelId {
    static let fluxKontextPro: Self = "flux-kontext-pro"
    static let fluxKontextMax: Self = "flux-kontext-max"
    static let fluxPro11Ultra: Self = "flux-pro-1.1-ultra"
    static let fluxPro11: Self = "flux-pro-1.1"
    static let fluxPro10Fill: Self = "flux-pro-1.0-fill"
}

public enum BlackForestLabsOutputFormat: String, Sendable, Codable {
    case jpeg
    case png
}

