/**
 Embeddings Example

 Demonstrates embedding text and calculating similarity.
 Corresponds to: apps/docs/src/content/docs/ai-sdk-core/embeddings.mdx
 */

import Foundation
import SwiftAISDK
import OpenAIProvider
import ExamplesCore

@main
struct EmbeddingsExample: CLIExample {
  static let name = "Embeddings & Similarity"
  static let description = "Generate embeddings and calculate similarity"

  static func run() async throws {
    // Example 1: Single embedding
    Logger.section("Example 1: Single Embedding")
    let single = try await embed(
      model: .v3(openai.textEmbeddingModel("text-embedding-3-small")),
      value: "sunny day at the beach"
    )

    Logger.info("Embedding dimensions: \(single.embedding.count)")
    Logger.info("First 5 values: \(single.embedding.prefix(5))")
    Logger.info("Tokens used: \(single.usage.tokens)")

    // Example 2: Batch embeddings
    Logger.section("Example 2: Batch Embeddings")
    let batch = try await embedMany(
      model: .v3(openai.textEmbeddingModel("text-embedding-3-small")),
      values: [
        "sunny day at the beach",
        "rainy afternoon in the city",
        "snowy night in the mountains"
      ]
    )

    Logger.info("Generated \(batch.embeddings.count) embeddings")
    Logger.info("Total tokens: \(batch.usage.tokens)")

    // Example 3: Cosine similarity
    Logger.section("Example 3: Cosine Similarity")
    let similarity = try await embedMany(
      model: .v3(openai.textEmbeddingModel("text-embedding-3-small")),
      values: [
        "sunny day at the beach",
        "rainy afternoon in the city"
      ]
    )

    let cosineSim = try cosineSimilarity(
      vector1: similarity.embeddings[0],
      vector2: similarity.embeddings[1]
    )

    Logger.info("Similarity between 'sunny beach' and 'rainy city': \(String(format: "%.4f", cosineSim))")

    // Example 4: Compare related vs unrelated text
    Logger.section("Example 4: Comparing Related vs Unrelated Text")
    let comparison = try await embedMany(
      model: .v3(openai.textEmbeddingModel("text-embedding-3-small")),
      values: [
        "The cat sat on the mat",
        "A feline rested on the rug",  // Similar meaning
        "Machine learning uses neural networks"  // Unrelated
      ]
    )

    let relatedSim = try cosineSimilarity(
      vector1: comparison.embeddings[0],
      vector2: comparison.embeddings[1]
    )

    let unrelatedSim = try cosineSimilarity(
      vector1: comparison.embeddings[0],
      vector2: comparison.embeddings[2]
    )

    Logger.info("Related texts similarity: \(String(format: "%.4f", relatedSim))")
    Logger.info("Unrelated texts similarity: \(String(format: "%.4f", unrelatedSim))")
    Logger.info("Difference: \(String(format: "%.4f", relatedSim - unrelatedSim))")
  }
}
