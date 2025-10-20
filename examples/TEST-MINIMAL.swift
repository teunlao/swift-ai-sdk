// Minimal test to see if API works
import Foundation
import SwiftAISDK
import OpenAIProvider

@main
struct TestMinimal {
  static func main() async throws {
    // Simplest possible call
    let x = try await generateText(
      model: .v3(openai("gpt-4o")),
      prompt: "Say hi"
    )
    print(x.text)
  }
}
