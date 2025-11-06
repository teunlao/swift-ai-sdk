import ExamplesCore
import OpenAIProvider
import SwiftAISDK

// Mirrors ai-core/src/complex/semantic-router example using Swift APIs.

struct SemanticRouterExample: Example {
  static let name = "complex/semantic-router"
  static let description = "Route text to a topic using embeddings + cosine similarity."

  enum Topic: String, Sendable, CaseIterable { case sports, music }

  struct Route<Name: Sendable & Hashable> {
    let name: Name
    let values: [String]
  }

  final class SemanticRouter<Name: Sendable & Hashable> {
    private let routes: [Route<Name>]
    private let embeddingModel: any EmbeddingModelV3<String>
    private let similarityThreshold: Double
    private var cached: [(name: Name, value: String, embedding: [Double])]? = nil

    init(
      routes: [Route<Name>],
      embeddingModel: any EmbeddingModelV3<String>,
      similarityThreshold: Double
    ) {
      self.routes = routes
      self.embeddingModel = embeddingModel
      self.similarityThreshold = similarityThreshold
    }

    private func routeEmbeddings() async throws -> [(name: Name, value: String, embedding: [Double])] {
      if let cached { return cached }
      var result: [(Name, String, [Double])] = []
      for route in routes {
        let em = try await embedMany(model: embeddingModel, values: route.values)
        for (idx, vec) in em.embeddings.enumerated() {
          result.append((route.name, route.values[idx], vec))
        }
      }
      self.cached = result
      return result
    }

    func route(value: String) async throws -> Name? {
      let valueEmbedding = try await embed(model: embeddingModel, value: value).embedding
      let candidates = try await routeEmbeddings()
      var best: (name: Name, sim: Double)? = nil
      for item in candidates {
        let sim = try cosineSimilarity(vector1: valueEmbedding, vector2: item.embedding)
        if sim >= similarityThreshold {
          if best == nil || sim > (best!.sim) {
            best = (item.name, sim)
          }
        }
      }
      return best?.name
    }
  }

  static func run() async throws {
    do {
      let router = SemanticRouter<Topic>(
        routes: [
          Route(name: .sports, values: [
            "who's your favorite football team?",
            "The World Cup is the most exciting event.",
            "I enjoy running marathons on weekends.",
          ]),
          Route(name: .music, values: [
            "what's your favorite genre of music?",
            "Classical music helps me concentrate.",
            "I recently attended a jazz festival.",
          ]),
        ],
        embeddingModel: openai.embedding("text-embedding-3-small"),
        similarityThreshold: 0.2
      )

      let input = "Many consider Michael Jordan the greatest basketball player ever."
      let topic = try await router.route(value: input)

      Logger.section("Input")
      Logger.info(input)

      Logger.section("Routed Topic")
      switch topic {
      case .some(.sports): Logger.info("sports")
      case .some(.music): Logger.info("music")
      case .none: Logger.info("no topic found")
      }
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}

