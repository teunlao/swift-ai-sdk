import Foundation

/**
 Experimental middleware for `LanguageModelV4`.

 Port of `@ai-sdk/provider/src/language-model-middleware/v4/language-model-v4-middleware.ts`.
 */
public struct LanguageModelV4Middleware: Sendable {
    public let specificationVersion: String
    public let overrideProvider: (@Sendable (_ model: any LanguageModelV4) -> String)?
    public let overrideModelId: (@Sendable (_ model: any LanguageModelV4) -> String)?
    public let overrideSupportedUrls: (@Sendable (_ model: any LanguageModelV4) async throws -> [String: [NSRegularExpression]])?
    public let transformParams: (@Sendable (_ type: OperationType, _ params: LanguageModelV4CallOptions, _ model: any LanguageModelV4) async throws -> LanguageModelV4CallOptions)?
    public let wrapGenerate: (@Sendable (
        _ doGenerate: @Sendable () async throws -> LanguageModelV4GenerateResult,
        _ doStream: @Sendable () async throws -> LanguageModelV4StreamResult,
        _ params: LanguageModelV4CallOptions,
        _ model: any LanguageModelV4
    ) async throws -> LanguageModelV4GenerateResult)?
    public let wrapStream: (@Sendable (
        _ doGenerate: @Sendable () async throws -> LanguageModelV4GenerateResult,
        _ doStream: @Sendable () async throws -> LanguageModelV4StreamResult,
        _ params: LanguageModelV4CallOptions,
        _ model: any LanguageModelV4
    ) async throws -> LanguageModelV4StreamResult)?

    public enum OperationType: String, Sendable {
        case generate
        case stream
    }

    public init(
        specificationVersion: String = "v4",
        overrideProvider: (@Sendable (_ model: any LanguageModelV4) -> String)? = nil,
        overrideModelId: (@Sendable (_ model: any LanguageModelV4) -> String)? = nil,
        overrideSupportedUrls: (@Sendable (_ model: any LanguageModelV4) async throws -> [String: [NSRegularExpression]])? = nil,
        transformParams: (@Sendable (_ type: OperationType, _ params: LanguageModelV4CallOptions, _ model: any LanguageModelV4) async throws -> LanguageModelV4CallOptions)? = nil,
        wrapGenerate: (@Sendable (
            _ doGenerate: @Sendable () async throws -> LanguageModelV4GenerateResult,
            _ doStream: @Sendable () async throws -> LanguageModelV4StreamResult,
            _ params: LanguageModelV4CallOptions,
            _ model: any LanguageModelV4
        ) async throws -> LanguageModelV4GenerateResult)? = nil,
        wrapStream: (@Sendable (
            _ doGenerate: @Sendable () async throws -> LanguageModelV4GenerateResult,
            _ doStream: @Sendable () async throws -> LanguageModelV4StreamResult,
            _ params: LanguageModelV4CallOptions,
            _ model: any LanguageModelV4
        ) async throws -> LanguageModelV4StreamResult)? = nil
    ) {
        self.specificationVersion = specificationVersion
        self.overrideProvider = overrideProvider
        self.overrideModelId = overrideModelId
        self.overrideSupportedUrls = overrideSupportedUrls
        self.transformParams = transformParams
        self.wrapGenerate = wrapGenerate
        self.wrapStream = wrapStream
    }
}
