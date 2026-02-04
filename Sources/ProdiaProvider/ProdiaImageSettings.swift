import Foundation

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/prodia/src/prodia-image-settings.ts
// Upstream commit: f3a72bc2a
//===----------------------------------------------------------------------===//

/// Prodia job types for image generation.
public struct ProdiaImageModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}

public extension ProdiaImageModelId {
    static let inferenceFluxFastSchnellTxt2imgV2: Self = "inference.flux-fast.schnell.txt2img.v2"
    static let inferenceFluxSchnellTxt2imgV2: Self = "inference.flux.schnell.txt2img.v2"
}

