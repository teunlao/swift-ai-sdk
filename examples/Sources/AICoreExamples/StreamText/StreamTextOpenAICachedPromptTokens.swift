import ExamplesCore
import Foundation
import OpenAIProvider
import SwiftAISDK

struct StreamTextOpenAICachedPromptTokensExample: Example {
  static let name = "stream-text/openai-cached-prompt-tokens"
  static let description = "Stream with a long prompt and observe cachedInputTokens in usage."

  static func run() async throws {
    let longPrompt = Self.longText

    do {
      let start = Date()
      let result: DefaultStreamTextResult<JSONValue, JSONValue> = try streamText(
        model: openai("gpt-4o-mini"),
        system: nil,
        messages: [
          .user(UserModelMessage(content: .text("What book is the following text from?: <text>\(longPrompt)</text>")))
        ],
        providerOptions: ["openai": ["maxCompletionTokens": 100]]
      )

      var response = ""
      for try await delta in result.textStream { response += delta; print(delta, terminator: "") }
      print("\n")

      let end = Date()
      Logger.section("Duration")
      Logger.info("\(Int(end.timeIntervalSince(start) * 1000)) ms")

      Logger.section("Usage")
      Helpers.printJSON(try await result.usage)
      Logger.section("Provider Metadata")
      if let meta = try await result.providerMetadata { Helpers.printJSON(meta) }
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }

  private static let longText = """
Arms and the man I sing, who first made way,
Predestined exile, from the Trojan shore
To Italy, the blest Lavinian strand.
Smitten of storms he was on land and sea
By violence of Heaven, to satisfy 5
Stern Juno’s sleepless wrath; and much in war
He suffered, seeking at the last to found
The city, and bring o’er his fathers’ gods
To safe abode in Latium; whence arose
The Latin race, old Alba’s reverend lords, 10
And from her hills wide-walled, imperial Rome.
"""
}
