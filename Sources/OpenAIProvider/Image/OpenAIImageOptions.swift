import Foundation

public let openAIImageModelMaxImagesPerCall: [OpenAIImageModelId: Int] = [
    "dall-e-3": 1,
    "dall-e-2": 10,
    "gpt-image-1": 10,
    "gpt-image-1-mini": 10
]

public let openAIImageModelsWithDefaultResponseFormat: Set<OpenAIImageModelId> = [
    "gpt-image-1",
    "gpt-image-1-mini"
]
