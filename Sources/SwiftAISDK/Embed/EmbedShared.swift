import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Shared helpers for the Embed API.

 Port of common utilities from `@ai-sdk/ai/src/embed/embed.ts` and
 `@ai-sdk/ai/src/embed/embed-many.ts`.
 */

// MARK: - Usage Helpers

func makeEmbeddingUsage(from usage: EmbeddingModelV3Usage?) -> EmbeddingModelUsage {
    EmbeddingModelUsage(tokens: usage.map { Double($0.tokens) } ?? .nan)
}

func makeEmbeddingUsage(from usage: EmbeddingModelV4Usage?) -> EmbeddingModelUsage {
    EmbeddingModelUsage(tokens: usage.map { Double($0.tokens) } ?? .nan)
}

func validateEmbeddingDimensions(_ dimensions: Int?) throws {
    if let dimensions, dimensions <= 0 {
        throw InvalidArgumentError(
            parameter: "dimensions",
            value: .number(Double(dimensions)),
            message: "dimensions must be a positive integer"
        )
    }
}

func validateEmbeddingCount(_ embeddings: [Embedding], values: [String]) throws {
    guard embeddings.count == values.count else {
        throw InvalidResponseDataError(
            data: embeddings,
            message: "Expected \(values.count) embeddings, but received \(embeddings.count)."
        )
    }
}

func splitEmbeddingValues(
    _ values: [String],
    maxEmbeddingsPerCall: Int,
    maxInputBytesPerCall: Int
) throws -> [[String]] {
    guard maxEmbeddingsPerCall > 0, maxInputBytesPerCall > 0 else {
        throw InvalidArgumentError(
            argument: maxEmbeddingsPerCall <= 0 ? "maxEmbeddingsPerCall" : "maxInputBytesPerCall",
            message: "Embedding call limits must be greater than 0"
        )
    }
    var chunks: [[String]] = []
    var chunk: [String] = []
    var bytes = 0
    for value in values {
        let inputBytes = value.utf8.count
        if !chunk.isEmpty && (chunk.count >= maxEmbeddingsPerCall || inputBytes > maxInputBytesPerCall - bytes) {
            chunks.append(chunk)
            chunk = []
            bytes = 0
        }
        chunk.append(value)
        bytes += inputBytes
    }
    if !chunk.isEmpty { chunks.append(chunk) }
    return chunks
}

// MARK: - Response and Warning Helpers

/// Converts legacy V3 response information into the public V4 embed result surface.
func makeEmbeddingResponseInfo(from response: EmbeddingModelV3ResponseInfo?) -> EmbeddingModelV4ResponseInfo? {
    response.map { EmbeddingModelV4ResponseInfo(headers: $0.headers, body: $0.body) }
}

/// Converts legacy V3 warnings into the V4 warning shape used by AI SDK results.
func makeEmbeddingWarning(from warning: SharedV3Warning) -> SharedV4Warning {
    switch warning {
    case let .unsupported(feature, details):
        return .unsupported(feature: feature, details: details)
    case let .compatibility(feature, details):
        return .compatibility(feature: feature, details: details)
    case .other(let message):
        return .other(message: message)
    }
}

// MARK: - Provider Metadata Merge

/// Merges provider metadata dictionaries in-place.
func mergeProviderMetadata(
    target: inout ProviderMetadata?,
    source: ProviderMetadata?
) {
    guard let source else {
        return
    }

    if target == nil {
        target = source
        return
    }

    for (provider, metadata) in source {
        var merged = target?[provider] ?? [:]
        for (key, value) in metadata {
            merged[key] = value
        }
        target?[provider] = merged
    }
}
