import Foundation
import AISDKProvider
import OpenAICompatibleProvider

public final class CerebrasChatLanguageModel: LanguageModelV4 {
    public let specificationVersion = "v4"
    public var modelId: String { base.modelId }
    public var provider: String { base.provider }
    public var supportedUrls: [String: [NSRegularExpression]] { get async throws { try await base.supportedUrls } }
    private let base: OpenAICompatibleChatLanguageModel
    public init(modelId: CerebrasChatModelId, config: OpenAICompatibleChatConfig) {
        base = .init(modelId: .init(rawValue: modelId.rawValue), config: config)
    }
    public func doGenerate(options: LanguageModelV4CallOptions) async throws -> LanguageModelV4GenerateResult {
        let result = try await base.doGenerate(options: options)
        guard case .json = options.responseFormat, result.finishReason.raw == "tool_calls",
              result.content.contains(where: { if case .text(let text) = $0 { return !text.text.isEmpty }; return false }) else { return result }
        return .init(content: result.content.filter { if case .toolCall = $0 { return false }; return true },
                     finishReason: .init(unified: .stop, raw: result.finishReason.raw), usage: result.usage,
                     providerMetadata: result.providerMetadata, request: result.request, response: result.response, warnings: result.warnings)
    }
    public func doStream(options: LanguageModelV4CallOptions) async throws -> LanguageModelV4StreamResult {
        let result = try await base.doStream(options: options)
        guard case .json = options.responseFormat else { return result }
        let stream = AsyncThrowingStream<LanguageModelV4StreamPart, Error> { continuation in
            let task = Task {
                var hasText = false
                do {
                    for try await part in result.stream {
                        if case .textDelta(_, let text, _) = part, !text.isEmpty { hasText = true }
                        if hasText {
                            switch part {
                            case .toolInputStart, .toolInputDelta, .toolInputEnd, .toolCall: continue
                            case .finish(let reason, let usage, let metadata) where reason.raw == "tool_calls":
                                continuation.yield(.finish(finishReason: .init(unified: .stop, raw: reason.raw), usage: usage, providerMetadata: metadata))
                                continue
                            default: break
                            }
                        }
                        continuation.yield(part)
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
        return .init(stream: stream, request: result.request, response: result.response)
    }
}

public struct CerebrasLanguageModelChatOptions: Codable, Sendable, Equatable {
    public var user: String?
    public var strictJsonSchema: Bool?
    public var parallelToolCalls: Bool?
    public var logprobs: Bool?
    public var topLogprobs: Int?
    public var logitBias: [String: Double]?
    public var serviceTier: String?
    public var reasoningEffort: String?
    public var reasoningFormat: String?
    public var prediction: JSONValue?
    public var promptCacheKey: String?
    public init() {}
}
