/**
 Experimental middleware for LanguageModelV2.

 Port of `@ai-sdk/provider/src/language-model-middleware/v2/language-model-v2-middleware.ts`.

 This type defines the structure for middleware that can be used to modify
 the behavior of LanguageModelV2 operations.
 */
import Foundation

public struct LanguageModelV2Middleware: Sendable {
    /**
     Middleware specification version. Use `v2` for the current version.
     */
    public let middlewareVersion: String?

    /**
     Override the provider name if desired.

     - Parameter model: The language model instance.
     - Returns: The overridden provider name.
     */
    public let overrideProvider: (@Sendable (_ model: any LanguageModelV2) -> String)?

    /**
     Override the model ID if desired.

     - Parameter model: The language model instance.
     - Returns: The overridden model ID.
     */
    public let overrideModelId: (@Sendable (_ model: any LanguageModelV2) -> String)?

    /**
     Override the supported URLs if desired.

     - Parameter model: The language model instance.
     - Returns: A dictionary mapping URL types to arrays of regular expression patterns (NSRegularExpression).
     */
    public let overrideSupportedUrls: (@Sendable (_ model: any LanguageModelV2) async throws -> [String: [NSRegularExpression]])?

    /**
     Transforms the parameters before they are passed to the language model.

     - Parameters:
       - type: The type of operation ('generate' or 'stream').
       - params: The original parameters for the language model call.
       - model: The language model instance.
     - Returns: The transformed parameters.
     */
    public let transformParams: (@Sendable (_ type: OperationType, _ params: LanguageModelV2CallOptions, _ model: any LanguageModelV2) async throws -> LanguageModelV2CallOptions)?

    /**
     Wraps the generate operation of the language model.

     - Parameters:
       - doGenerate: The original generate function.
       - doStream: The original stream function.
       - params: The parameters for the generate call. If the `transformParams` middleware is used, this will be the transformed parameters.
       - model: The language model instance.
     - Returns: The result of the generate operation.
     */
    public let wrapGenerate: (@Sendable (
        _ doGenerate: @Sendable () async throws -> LanguageModelV2GenerateResult,
        _ doStream: @Sendable () async throws -> LanguageModelV2StreamResult,
        _ params: LanguageModelV2CallOptions,
        _ model: any LanguageModelV2
    ) async throws -> LanguageModelV2GenerateResult)?

    /**
     Wraps the stream operation of the language model.

     - Parameters:
       - doGenerate: The original generate function.
       - doStream: The original stream function.
       - params: The parameters for the stream call. If the `transformParams` middleware is used, this will be the transformed parameters.
       - model: The language model instance.
     - Returns: The result of the stream operation.
     */
    public let wrapStream: (@Sendable (
        _ doGenerate: @Sendable () async throws -> LanguageModelV2GenerateResult,
        _ doStream: @Sendable () async throws -> LanguageModelV2StreamResult,
        _ params: LanguageModelV2CallOptions,
        _ model: any LanguageModelV2
    ) async throws -> LanguageModelV2StreamResult)?

    /// Operation type for language model calls
    public enum OperationType: String, Sendable {
        case generate
        case stream
    }

    /**
     Creates a new LanguageModelV2Middleware instance.

     - Parameters:
       - middlewareVersion: Optional middleware version (defaults to "v2").
       - overrideProvider: Optional provider override closure.
       - overrideModelId: Optional model ID override closure.
       - overrideSupportedUrls: Optional supported URLs override closure.
       - transformParams: Optional parameter transformation closure.
       - wrapGenerate: Optional generate operation wrapper closure.
       - wrapStream: Optional stream operation wrapper closure.
     */
    public init(
        middlewareVersion: String? = "v2",
        overrideProvider: (@Sendable (_ model: any LanguageModelV2) -> String)? = nil,
        overrideModelId: (@Sendable (_ model: any LanguageModelV2) -> String)? = nil,
        overrideSupportedUrls: (@Sendable (_ model: any LanguageModelV2) async throws -> [String: [NSRegularExpression]])? = nil,
        transformParams: (@Sendable (_ type: OperationType, _ params: LanguageModelV2CallOptions, _ model: any LanguageModelV2) async throws -> LanguageModelV2CallOptions)? = nil,
        wrapGenerate: (@Sendable (
            _ doGenerate: @Sendable () async throws -> LanguageModelV2GenerateResult,
            _ doStream: @Sendable () async throws -> LanguageModelV2StreamResult,
            _ params: LanguageModelV2CallOptions,
            _ model: any LanguageModelV2
        ) async throws -> LanguageModelV2GenerateResult)? = nil,
        wrapStream: (@Sendable (
            _ doGenerate: @Sendable () async throws -> LanguageModelV2GenerateResult,
            _ doStream: @Sendable () async throws -> LanguageModelV2StreamResult,
            _ params: LanguageModelV2CallOptions,
            _ model: any LanguageModelV2
        ) async throws -> LanguageModelV2StreamResult)? = nil
    ) {
        self.middlewareVersion = middlewareVersion
        self.overrideProvider = overrideProvider
        self.overrideModelId = overrideModelId
        self.overrideSupportedUrls = overrideSupportedUrls
        self.transformParams = transformParams
        self.wrapGenerate = wrapGenerate
        self.wrapStream = wrapStream
    }
}
