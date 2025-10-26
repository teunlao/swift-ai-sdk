import Foundation

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/amazon-bedrock/src/bedrock-image-settings.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public let bedrockModelMaxImagesPerCall: [BedrockImageModelId: Int] = [
    .amazonNovaCanvasV1: 5
]
