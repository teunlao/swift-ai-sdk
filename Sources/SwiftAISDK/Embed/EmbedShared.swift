import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Shared helpers for the Embed API.

 Port of common utilities from `@ai-sdk/ai/src/embed/embed.ts` and
 `@ai-sdk/ai/src/embed/embed-many.ts`.
 */

// MARK: - Usage Helpers

func makeEmbeddingUsage(from usage: EmbeddingModelV4Usage?) -> EmbeddingModelUsage {
    EmbeddingModelUsage(tokens: usage?.tokens ?? 0)
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
