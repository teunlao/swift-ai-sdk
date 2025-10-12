/**
 * Model not found error.
 *
 * Swift port of TypeScript `NoSuchModelError`.
 */
public struct NoSuchModelError: AISDKError, Sendable {
    public static let errorDomain = "vercel.ai.error.AI_NoSuchModelError"

    public let name: String
    public let message: String
    public let cause: (any Error)? = nil
    public let modelId: String
    public let modelType: ModelType

    public enum ModelType: String, Sendable {
        case languageModel
        case textEmbeddingModel
        case imageModel
        case transcriptionModel
        case speechModel
    }

    public init(
        errorName: String = "AI_NoSuchModelError",
        modelId: String,
        modelType: ModelType,
        message: String? = nil
    ) {
        self.name = errorName
        self.modelId = modelId
        self.modelType = modelType
        self.message = message ?? "No such \(modelType.rawValue): \(modelId)"
    }

    /// Check if an error is an instance of NoSuchModelError
    public static func isInstance(_ error: any Error) -> Bool {
        SwiftAISDK.hasMarker(error, marker: errorDomain)
    }
}
