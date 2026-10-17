import Foundation
import AISDKProvider
import AISDKProviderUtils

public final class GatewayLanguageModel: LanguageModelV4 {
    private static let wildcardRegex = try! NSRegularExpression(pattern: ".*")
    private let modelIdentifier: GatewayModelId
    private let config: GatewayLanguageModelConfig

    init(modelId: GatewayModelId, config: GatewayLanguageModelConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }
    public var supportedUrls: [String: [NSRegularExpression]] { ["*/*": [Self.wildcardRegex]] }

    public func doGenerate(options: LanguageModelV4CallOptions) async throws -> LanguageModelV4GenerateResult {
        let body = try gatewayJSON(GatewayLanguageModelRequestBody(options: options))
        let headers = try await config.headers()
        do {
            let response = try await postJsonToAPI(
                url: "\(config.baseURL)/language-model",
                headers: try await requestHeaders(options: options, resolved: headers, streaming: false),
                body: body,
                failedResponseHandler: makeGatewayFailedResponseHandler(),
                successfulResponseHandler: createJsonResponseHandler(responseSchema: gatewaySchema(GatewayLanguageResponse.self)),
                isAborted: options.abortSignal,
                fetch: config.fetch
            )
            return LanguageModelV4GenerateResult(
                content: response.value.content,
                finishReason: response.value.finishReason,
                usage: response.value.usage,
                providerMetadata: response.value.providerMetadata,
                request: .init(body: jsonValueToFoundation(body)),
                response: .init(headers: response.responseHeaders, body: response.rawValue),
                warnings: response.value.warnings ?? []
            )
        } catch {
            throw asGatewayError(error, authMethod: parseAuthMethod(from: headers.compactMapValues { $0 }))
        }
    }

    public func doStream(options: LanguageModelV4CallOptions) async throws -> LanguageModelV4StreamResult {
        let body = try gatewayJSON(GatewayLanguageModelRequestBody(options: options))
        let headers = try await config.headers()
        do {
            let response = try await postJsonToAPI(
                url: "\(config.baseURL)/language-model",
                headers: try await requestHeaders(options: options, resolved: headers, streaming: true),
                body: body,
                failedResponseHandler: makeGatewayFailedResponseHandler(),
                successfulResponseHandler: createEventSourceResponseHandler(chunkSchema: gatewaySchema(LanguageModelV4StreamPart.self)),
                isAborted: options.abortSignal,
                fetch: config.fetch
            )
            let stream = AsyncThrowingStream<LanguageModelV4StreamPart, Error> { continuation in
                let task = Task {
                    do {
                        for try await chunk in response.value {
                            switch chunk {
                            case .success(let part, _):
                                if case .raw = part, options.includeRawChunks != true { continue }
                                continuation.yield(part)
                            case .failure(let error, _):
                                throw error
                            }
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in task.cancel() }
            }
            return LanguageModelV4StreamResult(
                stream: stream,
                request: .init(body: jsonValueToFoundation(body)),
                response: .init(headers: response.responseHeaders)
            )
        } catch {
            throw asGatewayError(error, authMethod: parseAuthMethod(from: headers.compactMapValues { $0 }))
        }
    }

    private func requestHeaders(
        options: LanguageModelV4CallOptions,
        resolved: [String: String?],
        streaming: Bool
    ) async throws -> [String: String] {
        combineHeaders(
            resolved,
            options.headers?.mapValues { Optional($0) },
            [
                "ai-language-model-specification-version": "4",
                "ai-language-model-id": modelId,
                "ai-language-model-streaming": String(streaming)
            ],
            try await config.o11yHeaders()
        ).compactMapValues { $0 }
    }
}

private struct GatewayLanguageResponse: Decodable, Sendable {
    let content: [LanguageModelV4Content]
    let finishReason: LanguageModelV4FinishReason
    let usage: LanguageModelV4Usage
    let providerMetadata: SharedV4ProviderMetadata?
    let warnings: [SharedV4Warning]?
}

private struct GatewayLanguageModelRequestBody: Encodable {
    let prompt: LanguageModelV4Prompt
    let maxOutputTokens: Int?
    let temperature: Double?
    let stopSequences: [String]?
    let topP: Double?
    let topK: Int?
    let presencePenalty: Double?
    let frequencyPenalty: Double?
    let responseFormat: LanguageModelV4ResponseFormat?
    let seed: Int?
    let tools: [LanguageModelV4Tool]?
    let toolChoice: LanguageModelV4ToolChoice?
    let includeRawChunks: Bool?
    let headers: SharedV4Headers?
    let reasoning: LanguageModelV4ReasoningEffort?
    let providerOptions: SharedV4ProviderOptions?

    init(options: LanguageModelV4CallOptions) {
        // V4 file data encodes binary bytes as tagged base64, including nested tool results.
        prompt = options.prompt
        maxOutputTokens = options.maxOutputTokens
        temperature = options.temperature
        stopSequences = options.stopSequences
        topP = options.topP
        topK = options.topK
        presencePenalty = options.presencePenalty
        frequencyPenalty = options.frequencyPenalty
        responseFormat = options.responseFormat
        seed = options.seed
        tools = options.tools
        toolChoice = options.toolChoice
        includeRawChunks = options.includeRawChunks
        headers = options.headers
        reasoning = options.reasoning
        providerOptions = options.providerOptions
    }
}
