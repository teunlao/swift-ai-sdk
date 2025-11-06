import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct StreamTextOpenAIResponsesFileSearchExample: Example {
  static let name = "stream-text/openai-responses-file-search"
  static let description = "OpenAI Responses with the fileSearch tool (requires OPENAI_VECTOR_STORE_ID)."

  static func run() async throws {
    // Requires an OpenAI vector store.
    let vectorStoreId = EnvLoader.get("OPENAI_VECTOR_STORE_ID")
    guard !vectorStoreId.isEmpty else {
      Logger.warning("OPENAI_VECTOR_STORE_ID not set—skipping the fileSearch example.")
      return
    }

    do {
      let args = OpenAIFileSearchArgs(
        vectorStoreIds: [vectorStoreId],
        maxNumResults: 5,
        ranking: .init(ranker: nil, scoreThreshold: nil),
        filters: nil
      )

      let fileSearch = openai.tools.fileSearch(args)

      // Request file_search results in the response (if the provider returns them).
      let providerOptions = openai.options.responses(include: [.fileSearchCallResults])

      let result = try streamText(
        model: openai.responses(modelId: "gpt-4o-mini"),
        prompt: "Find facts about Swift Package Manager from the vector store and summarize in 2 bullets.",
        tools: [
          "file_search": fileSearch
        ],
        providerOptions: providerOptions
      )

      Logger.section("Streamed output")
      for try await delta in result.textStream { print(delta, terminator: "") }
      print("")

      Logger.section("Finish reason")
      Logger.info((try await result.finishReason).rawValue)

      Logger.section("Usage")
      Helpers.printJSON(try await result.usage)
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}
