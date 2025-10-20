/**
 Speech Generation Example

 Demonstrates text-to-speech with OpenAI TTS.
 Corresponds to: apps/docs/src/content/docs/ai-sdk-core/speech.mdx
 */

import Foundation
import SwiftAISDK
import OpenAIProvider
import ExamplesCore

@main
struct SpeechExample: CLIExample {
  static let name = "Speech Generation (TTS)"
  static let description = "Generate speech from text"

  static func run() async throws {
    // Example 1: Basic speech generation
    Logger.section("Example 1: Basic Speech Generation")
    Logger.info("Generating speech with 'alloy' voice...")

    let audio = try await generateSpeech(
      model: openai.speech(modelId: "tts-1"),
      text: "Hello from Swift AI SDK! This is a test of text-to-speech generation.",
      voice: "alloy"
    )

    Logger.info("Audio generated successfully!")
    Logger.info("Audio data size: \(audio.audio.data.count) bytes")
    Logger.info("Format: MP3")

    // Example 2: Different voice
    Logger.section("Example 2: Different Voice (Nova)")
    Logger.info("Generating speech with 'nova' voice...")

    let nova = try await generateSpeech(
      model: openai.speech(modelId: "tts-1"),
      text: "The Swift AI SDK makes it easy to work with language models.",
      voice: "nova"
    )

    Logger.info("Nova voice audio generated")
    Logger.info("Data size: \(nova.audio.data.count) bytes")

    // Example 3: HD quality
    Logger.section("Example 3: HD Quality (tts-1-hd)")
    Logger.info("Generating HD quality speech...")

    let hd = try await generateSpeech(
      model: openai.speech(modelId: "tts-1-hd"),
      text: "High definition audio provides better quality for professional use.",
      voice: "shimmer"
    )

    Logger.info("HD audio generated")
    Logger.info("Data size: \(hd.audio.data.count) bytes")

    // Example 4: Different speed
    Logger.section("Example 4: Custom Speed")
    Logger.info("Generating speech at 1.25x speed...")

    let fast = try await generateSpeech(
      model: openai.speech(modelId: "tts-1"),
      text: "This audio is generated at a faster playback speed.",
      voice: "fable",
      providerOptions: ["openai": [
        "speed": 1.25
      ]]
    )

    Logger.info("Fast speech generated")
    Logger.info("Data size: \(fast.audio.data.count) bytes")

    // Show summary
    Logger.separator()
    Logger.info("Total audio clips generated: 4")
    Logger.info("Available voices: alloy, echo, fable, onyx, nova, shimmer")
    Logger.info("Tip: Use audio.audio.data to save the MP3 file")
  }
}
