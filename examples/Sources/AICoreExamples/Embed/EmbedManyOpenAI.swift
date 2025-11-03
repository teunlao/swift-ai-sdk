import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct EmbedManyOpenAIExample: Example {
  static let name = "embed-many/openai"
  static let description = "Embed multiple texts using OpenAI (text-embedding-3-small)."

  static func run() async throws {
    do {
      let values = [
        "sunny day at the beach",
        "rainy afternoon in the city",
        "snowy night in the mountains",
      ]

      let result = try await embedMany(
        model: openai.embedding("text-embedding-3-small"),
        values: values
      )

      Logger.section("Embeddings shape")
      Logger.info("count: \(result.embeddings.count)")
      if let first = result.embeddings.first {
        Logger.info("dims: \(first.count)")
      }

      // Simple cosine similarity between first two vectors
      if result.embeddings.count >= 2 {
        let sim = cosine(result.embeddings[0], result.embeddings[1])
        Logger.section("Cosine similarity [0,1]")
        Logger.info(String(format: "%.4f", sim))
      }

      Logger.section("Usage")
      Helpers.printJSON(result.usage)
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }

  private static func cosine(_ a: [Double], _ b: [Double]) -> Double {
    guard a.count == b.count, a.count > 0 else { return 0 }
    var dot = 0.0, na = 0.0, nb = 0.0
    for i in 0..<a.count {
      dot += a[i] * b[i]
      na += a[i] * a[i]
      nb += b[i] * b[i]
    }
    let denom = (na.squareRoot() * nb.squareRoot())
    return denom > 0 ? dot / denom : 0
  }
}

