import Foundation

/// Replicate image model identifier.
/// Mirrors `packages/replicate/src/replicate-image-settings.ts`.
public struct ReplicateImageModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}

// MARK: - Known model IDs (from upstream)
// Mirrors `packages/replicate/src/replicate-image-settings.ts`.
public extension ReplicateImageModelId {
    // black-forest-labs
    static let flux11Pro: Self = "black-forest-labs/flux-1.1-pro"
    static let flux11ProUltra: Self = "black-forest-labs/flux-1.1-pro-ultra"
    static let fluxDev: Self = "black-forest-labs/flux-dev"
    static let fluxPro: Self = "black-forest-labs/flux-pro"
    static let fluxSchnell: Self = "black-forest-labs/flux-schnell"

    // bytedance
    static let sdxlLightning4Step: Self = "bytedance/sdxl-lightning-4step"

    // fofr
    static let auraFlow: Self = "fofr/aura-flow"
    static let latentConsistencyModel: Self = "fofr/latent-consistency-model"
    static let realvisxlV3MultiControlnetLora: Self = "fofr/realvisxl-v3-multi-controlnet-lora"
    static let sdxlEmoji: Self = "fofr/sdxl-emoji"
    static let sdxlMultiControlnetLora: Self = "fofr/sdxl-multi-controlnet-lora"

    // ideogram-ai
    static let ideogramV2: Self = "ideogram-ai/ideogram-v2"
    static let ideogramV2Turbo: Self = "ideogram-ai/ideogram-v2-turbo"

    // lucataco
    static let dreamshaperXLTurbo: Self = "lucataco/dreamshaper-xl-turbo"
    static let openDalleV11: Self = "lucataco/open-dalle-v1.1"
    static let realvisxlV20: Self = "lucataco/realvisxl-v2.0"
    static let realvisxl2LCM: Self = "lucataco/realvisxl2-lcm"

    // luma
    static let photon: Self = "luma/photon"
    static let photonFlash: Self = "luma/photon-flash"

    // nvidia
    static let sana: Self = "nvidia/sana"

    // playgroundai
    static let playgroundV25Aesthetic: Self = "playgroundai/playground-v2.5-1024px-aesthetic"

    // recraft-ai
    static let recraftV3: Self = "recraft-ai/recraft-v3"
    static let recraftV3SVG: Self = "recraft-ai/recraft-v3-svg"

    // stability-ai
    static let sd35Large: Self = "stability-ai/stable-diffusion-3.5-large"
    static let sd35LargeTurbo: Self = "stability-ai/stable-diffusion-3.5-large-turbo"
    static let sd35Medium: Self = "stability-ai/stable-diffusion-3.5-medium"

    // tstramer
    static let materialDiffusion: Self = "tstramer/material-diffusion"
}
