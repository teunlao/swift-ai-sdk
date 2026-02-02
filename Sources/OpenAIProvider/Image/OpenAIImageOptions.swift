import Foundation

public let openAIImageModelMaxImagesPerCall: [OpenAIImageModelId: Int] = [
    "dall-e-3": 1,
    "dall-e-2": 10,
    "gpt-image-1": 10,
    "gpt-image-1-mini": 10,
    "gpt-image-1.5": 10
]

private let openAIDefaultImageResponseFormatPrefixes: [String] = [
    "gpt-image-1-mini",
    "gpt-image-1.5",
    "gpt-image-1"
]

func openAIImageHasDefaultResponseFormat(modelId: OpenAIImageModelId) -> Bool {
    openAIDefaultImageResponseFormatPrefixes.contains { modelId.rawValue.hasPrefix($0) }
}
