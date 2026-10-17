import AISDKProvider
import AISDKProviderUtils
import OpenAIProvider

public final class AzureImageModel: ImageModelV4 {
    public let modelId: String
    public let provider = "azure.image"
    private let openai: OpenAIImageModel
    private let mai: AzureMaiImageModel

    public init(modelId: String, openai: OpenAIImageModel, mai: AzureMaiImageModel) {
        self.modelId = modelId
        self.openai = openai
        self.mai = mai
    }

    private var defaultModel: any ImageModelV4 { isMaiImageModel(modelId) ? mai : openai }
    public var maxImagesPerCall: ImageModelV4MaxImagesPerCall { defaultModel.maxImagesPerCall }
    public var supportsFileInputs: Bool? { get async throws { try await defaultModel.supportsFileInputs } }
    public var supportsMaskInputs: Bool? { get async throws { try await defaultModel.supportsMaskInputs } }

    public func doGenerate(options: ImageModelV4CallOptions) async throws -> ImageModelV4GenerateResult {
        let settings = try await parseProviderOptions(provider: "azure", providerOptions: options.providerOptions,
            schema: azureImageModelOptions) ?? .init()
        if (settings.api ?? (isMaiImageModel(modelId) ? .mai : .openai)) == .mai {
            return try await mai.doGenerate(options: options,
                maiOptions: .init(autoAspectRatio: settings.autoAspectRatio, webGrounding: settings.webGrounding))
        }
        let result = try await openai.doGenerate(options: options)
        var warnings = result.warnings
        for (key, value) in [("autoAspectRatio", settings.autoAspectRatio), ("webGrounding", settings.webGrounding)] where value != nil {
            warnings.append(.unsupported(feature: "providerOptions.azure.\(key)", details: "This option requires the MAI image API."))
        }
        return .init(images: result.images, isRetryable: result.isRetryable, warnings: warnings,
            providerMetadata: result.providerMetadata, response: result.response, usage: result.usage)
    }
}
