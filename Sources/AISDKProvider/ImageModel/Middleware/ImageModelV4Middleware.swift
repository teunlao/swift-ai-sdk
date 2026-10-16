/**
 Middleware for `ImageModelV4`.

 Port of `@ai-sdk/provider/src/image-model-middleware/v4/image-model-v4-middleware.ts`.
 */
public struct ImageModelV4Middleware: Sendable {
    public let specificationVersion: String
    public let overrideProvider: (@Sendable (_ model: any ImageModelV4) -> String)?
    public let overrideModelId: (@Sendable (_ model: any ImageModelV4) -> String)?
    public let overrideMaxImagesPerCall: (@Sendable (_ model: any ImageModelV4) -> ImageModelV4MaxImagesPerCall)?
    /// Overrides whether the model supports image file inputs; `nil` marks support as unknown.
    public let overrideSupportsFileInputs: (@Sendable (_ model: any ImageModelV4) async throws -> Bool?)?
    /// Overrides whether the model supports mask inputs; `nil` marks support as unknown.
    public let overrideSupportsMaskInputs: (@Sendable (_ model: any ImageModelV4) async throws -> Bool?)?
    public let transformParams: (@Sendable (_ params: ImageModelV4CallOptions, _ model: any ImageModelV4) async throws -> ImageModelV4CallOptions)?
    public let wrapGenerate: (@Sendable (
        _ doGenerate: @Sendable () async throws -> ImageModelV4GenerateResult,
        _ params: ImageModelV4CallOptions,
        _ model: any ImageModelV4
    ) async throws -> ImageModelV4GenerateResult)?

    public init(
        specificationVersion: String = "v4",
        overrideProvider: (@Sendable (_ model: any ImageModelV4) -> String)? = nil,
        overrideModelId: (@Sendable (_ model: any ImageModelV4) -> String)? = nil,
        overrideMaxImagesPerCall: (@Sendable (_ model: any ImageModelV4) -> ImageModelV4MaxImagesPerCall)? = nil,
        overrideSupportsFileInputs: (@Sendable (_ model: any ImageModelV4) async throws -> Bool?)? = nil,
        overrideSupportsMaskInputs: (@Sendable (_ model: any ImageModelV4) async throws -> Bool?)? = nil,
        transformParams: (@Sendable (_ params: ImageModelV4CallOptions, _ model: any ImageModelV4) async throws -> ImageModelV4CallOptions)? = nil,
        wrapGenerate: (@Sendable (
            _ doGenerate: @Sendable () async throws -> ImageModelV4GenerateResult,
            _ params: ImageModelV4CallOptions,
            _ model: any ImageModelV4
        ) async throws -> ImageModelV4GenerateResult)? = nil
    ) {
        self.specificationVersion = specificationVersion
        self.overrideProvider = overrideProvider
        self.overrideModelId = overrideModelId
        self.overrideMaxImagesPerCall = overrideMaxImagesPerCall
        self.overrideSupportsFileInputs = overrideSupportsFileInputs
        self.overrideSupportsMaskInputs = overrideSupportsMaskInputs
        self.transformParams = transformParams
        self.wrapGenerate = wrapGenerate
    }
}
