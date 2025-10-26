import Foundation

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/luma/src/luma-image-settings.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

/// Wrapper for Luma image model identifiers.
/// Mirrors `LumaImageModelId` union from upstream TypeScript.
public struct LumaImageModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}

public extension LumaImageModelId {
    /// High fidelity Photon model (default).
    static let photon1: Self = "photon-1"
    /// Fast Photon Flash model for rapid iteration.
    static let photonFlash1: Self = "photon-flash-1"
}
