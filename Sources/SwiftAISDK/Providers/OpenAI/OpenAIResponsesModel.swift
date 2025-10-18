import Foundation
import AISDKProvider
import AISDKProviderUtils

public final class OpenAIResponsesLanguageModel: LanguageModelV3 {
    public let specificationVersion: String = "v3"
    private let modelIdentifier: OpenAIResponsesModelId
    private let config: OpenAIConfig

    public init(modelId: OpenAIResponsesModelId, config: OpenAIConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }

    public var supportedUrls: [String: [NSRegularExpression]] {
        get async throws { [:] }
    }

    public func doStream(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3StreamResult {
        throw UnsupportedFunctionalityError(functionality: "OpenAI responses streaming not yet implemented")
    }

    public func doGenerate(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3GenerateResult {
        let (input, inputWarnings) = try await OpenAIResponsesInputBuilder.makeInput(
            prompt: options.prompt,
            systemMessageMode: .system,
            fileIdPrefixes: config.fileIdPrefixes,
            store: true
        )

        let requestBody = OpenAIResponsesRequest(
            model: modelIdentifier.rawValue,
            input: input,
            temperature: options.temperature,
            topP: options.topP,
            maxOutputTokens: options.maxOutputTokens
        )

        let url = config.url(.init(modelId: modelIdentifier.rawValue, path: "/responses"))
        let headers = combineHeaders(config.headers(), options.headers?.mapValues { Optional($0) })
        let normalizedHeaders = headers.compactMapValues { $0 }

        let response = try await postJsonToAPI(
            url: url,
            headers: normalizedHeaders,
            body: requestBody,
            failedResponseHandler: openAIFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: openAIResponsesResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let value = response.value

        let content: [LanguageModelV3Content] = value.output.compactMap { item in
            guard item.type == "output_text", let text = item.text else { return nil }
            return .text(LanguageModelV3Text(text: text, providerMetadata: nil))
        }

        let usage = LanguageModelV3Usage(
            inputTokens: value.usage?.inputTokens,
            outputTokens: value.usage?.outputTokens,
            totalTokens: value.usage?.totalTokens
        )

        let finishReason = mapOpenAIResponsesFinishReason(value.finishReason)
        
        return LanguageModelV3GenerateResult(
            content: content,
            finishReason: finishReason,
            usage: usage,
            providerMetadata: nil,
            request: LanguageModelV3RequestInfo(body: requestBody),
            response: LanguageModelV3ResponseInfo(
                id: value.id,
                timestamp: nil,
                modelId: modelIdentifier.rawValue,
                headers: response.responseHeaders,
                body: nil
            ),
            warnings: inputWarnings
        )
    }

}

private struct OpenAIResponsesRequest: Encodable, Sendable {
    let model: String
    let input: OpenAIResponsesInput
    let temperature: Double?
    let topP: Double?
    let maxOutputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case model
        case input
        case temperature
        case topP = "top_p"
        case maxOutputTokens = "max_output_tokens"
    }
}
