/**
 Image Generation Example

 Demonstrates generating images with DALL-E.
 Corresponds to: apps/docs/src/content/docs/ai-sdk-core/image-generation.mdx
 */

import Foundation
import SwiftAISDK
import OpenAIProvider
import ExamplesCore

@main
struct ImageGenerationExample: CLIExample {
  static let name = "Image Generation"
  static let description = "Generate images with DALL-E"

  static func run() async throws {
    // Example 1: Basic image generation
    Logger.section("Example 1: Basic Image Generation")
    Logger.info("Generating image with DALL-E 3...")

    let result = try await generateImage(
      model: openai.image("dall-e-3"),
      prompt: "A futuristic city with flying cars at sunset"
    )

    let image = result.image
    Logger.info("Image generated successfully!")
    Logger.info("Format: \(image.base64.prefix(50))... (base64)")
    Logger.info("Image data size: \(image.data.count) bytes")

    // Example 2: With specific size
    Logger.section("Example 2: With Size Setting")
    Logger.info("Generating 1792x1024 image...")

    let sized = try await generateImage(
      model: openai.image("dall-e-3"),
      prompt: "A majestic mountain landscape with aurora borealis",
      size: "1792x1024"
    )

    Logger.info("Generated image size: 1792x1024")
    Logger.info("Data size: \(sized.image.data.count) bytes")

    // Example 3: With aspect ratio and quality
    Logger.section("Example 3: With Quality and Style")
    Logger.info("Generating HD quality image...")

    let quality = try await generateImage(
      model: openai.image("dall-e-3"),
      prompt: "An elegant steampunk airship in detailed Victorian style",
      providerOptions: ["openai": [
        "quality": "hd",
        "style": "vivid"
      ]]
    )

    Logger.info("HD image generated")
    Logger.info("Data size: \(quality.image.data.count) bytes")

    // Show usage information
    Logger.separator()
    Logger.info("Total images generated: 3")
    Logger.info("All images saved as base64 data")
  }
}
