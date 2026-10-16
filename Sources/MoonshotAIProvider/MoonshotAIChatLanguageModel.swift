import AISDKProvider
import AISDKProviderUtils
import Foundation
import OpenAICompatibleProvider

/// MoonshotAI chat model built on top of the OpenAI-compatible chat language model.
///
/// Mirrors `packages/moonshotai/src/moonshotai-chat-language-model.ts`.
public final class MoonshotAIChatLanguageModel: LanguageModelV4 {
    public let specificationVersion: String = "v4"

    private let base: OpenAICompatibleChatLanguageModelV4

    public init(modelId: MoonshotAIChatModelId, config: OpenAICompatibleChatConfig) {
        self.base = OpenAICompatibleChatLanguageModelV4(
            modelId: OpenAICompatibleChatModelId(rawValue: modelId.rawValue),
            config: config
        )
    }

    public var provider: String { base.provider }
    public var modelId: String { base.modelId }

    public var supportedUrls: [String: [NSRegularExpression]] {
        get async throws { try await base.supportedUrls }
    }

    public func doGenerate(options: LanguageModelV4CallOptions) async throws -> LanguageModelV4GenerateResult {
        let result = try await base.doGenerate(options: options)

        let usageRaw = extractUsage(from: result.response?.body) ?? result.usage.raw
        let converted = convertMoonshotAIChatUsage(usageRaw)

        return LanguageModelV4GenerateResult(
            content: result.content,
            finishReason: result.finishReason,
            usage: converted,
            providerMetadata: result.providerMetadata,
            request: result.request,
            response: result.response,
            warnings: result.warnings
        )
    }

    public func doStream(options: LanguageModelV4CallOptions) async throws -> LanguageModelV4StreamResult {
        let result = try await base.doStream(options: options)

        let stream = AsyncThrowingStream<LanguageModelV4StreamPart, Error>(bufferingPolicy: .unbounded) { continuation in
            Task {
                do {
                    for try await part in result.stream {
                        switch part {
                        case let .finish(finishReason: finishReason, usage: usage, providerMetadata: providerMetadata):
                            let converted = convertMoonshotAIChatUsage(usage.raw)
                            continuation.yield(.finish(
                                finishReason: finishReason,
                                usage: converted,
                                providerMetadata: providerMetadata
                            ))
                        default:
                            continuation.yield(part)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }

        return LanguageModelV4StreamResult(
            stream: stream,
            request: result.request,
            response: result.response
        )
    }

    private func extractUsage(from responseBody: Any?) -> JSONValue? {
        guard let responseBody else { return nil }
        guard let json = try? jsonValue(from: responseBody) else { return nil }
        guard case .object(let dict) = json else { return nil }
        guard let usage = dict["usage"], usage != .null else { return nil }
        return usage
    }
}

