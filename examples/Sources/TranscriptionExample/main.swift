/**
 Transcription Example

 Demonstrates audio-to-text transcription with Whisper.
 Corresponds to: apps/docs/src/content/docs/ai-sdk-core/transcription.mdx
 */

import Foundation
import SwiftAISDK
import OpenAIProvider
import ExamplesCore

@main
struct TranscriptionExample: CLIExample {
  static let name = "Audio Transcription"
  static let description = "Transcribe audio to text with Whisper"

  static func run() async throws {
    Logger.info("Note: This example requires an audio file to transcribe.")
    Logger.info("For demonstration, we'll generate synthetic audio first using TTS.")
    Logger.separator()

    // Generate sample audio first (since we need something to transcribe)
    Logger.section("Step 1: Generate Sample Audio")
    Logger.info("Creating sample audio with TTS...")

    let sampleAudio = try await generateSpeech(
      model: openai.speech("tts-1"),
      text: "The Swift AI SDK provides a unified interface for working with multiple language model providers.",
      voice: "alloy"
    )

    Logger.info("Sample audio generated: \(sampleAudio.audio.data.count) bytes")

    // Example 1: Basic transcription
    Logger.section("Step 2: Transcribe Audio")
    Logger.info("Transcribing audio with Whisper...")

    let transcript = try await transcribe(
      model: openai.transcription("whisper-1"),
      audio: .data(sampleAudio.audio.data)
    )

    Logger.info("Transcription: \(transcript.text)")

    // Example 2: With language hint
    Logger.section("Example 2: With Language Hint")
    Logger.info("Transcribing with language hint (English)...")

    let withLang = try await transcribe(
      model: openai.transcription("whisper-1"),
      audio: .data(sampleAudio.audio.data),
      providerOptions: ["openai": [
        "language": "en"
      ]]
    )

    Logger.info("Transcription: \(withLang.text)")
    if let language = withLang.language {
      Logger.info("Detected language: \(language)")
    }

    // Example 3: With timestamp granularities
    Logger.section("Example 3: With Word Timestamps")
    Logger.info("Transcribing with word-level timestamps...")

    let withTimestamps = try await transcribe(
      model: openai.transcription("whisper-1"),
      audio: .data(sampleAudio.audio.data),
      providerOptions: ["openai": [
        "timestampGranularities": ["word"]
      ]]
    )

    Logger.info("Transcription: \(withTimestamps.text)")
    let segments = withTimestamps.segments
    Logger.info("Number of word segments: \(segments.count)")
    if let first = segments.first {
      Logger.info("First segment: '\(first.text)'")
    }

    // Show summary
    Logger.separator()
    Logger.info("Transcription complete!")
    Logger.info("Model: whisper-1 (OpenAI)")
    Logger.info("Audio format: MP3 (from TTS)")
    Logger.info("Supported formats: mp3, mp4, mpeg, mpga, m4a, wav, webm")
  }
}
