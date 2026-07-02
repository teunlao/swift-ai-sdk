/**
 Middleware for `ImageModelV4`.

 Port of `@ai-sdk/provider/src/image-model-middleware/v4/image-model-v4-middleware.ts`.
 */
public struct ImageModelV4Middleware: Sendable {
    public let specificationVersion: String
    public let overrideProvider: (@Sendable (_ model: any ImageModelV4) -> String)?
    public let overrideModelId: (@Sendable (_ model: any ImageModelV4) -> String)?
    public let overrideMaxImagesPerCall: (@Sendable (_ model: any ImageModelV4) -> ImageModelV4MaxImagesPerCall)?
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
        self.transformParams = transformParams
        self.wrapGenerate = wrapGenerate
    }
}
