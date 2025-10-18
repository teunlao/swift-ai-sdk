import Foundation
import AISDKProvider
import AISDKProviderUtils

struct OpenAITranscriptionResponse: Codable, Sendable {
    struct Word: Codable, Sendable {
        let word: String
        let start: Double
        let end: Double
    }

    struct Segment: Codable, Sendable {
        let id: Int
        let seek: Int
        let start: Double
        let end: Double
        let text: String
        let tokens: [Int]
        let temperature: Double
        let avgLogprob: Double
        let compressionRatio: Double
        let noSpeechProb: Double

        enum CodingKeys: String, CodingKey {
            case id
            case seek
            case start
            case end
            case text
            case tokens
            case temperature
            case avgLogprob = "avg_logprob"
            case compressionRatio = "compression_ratio"
            case noSpeechProb = "no_speech_prob"
        }
    }

    let text: String
    let language: String?
    let duration: Double?
    let words: [Word]?
    let segments: [Segment]?

    enum CodingKeys: String, CodingKey {
        case text
        case language
        case duration
        case words
        case segments
    }
}

let openAITranscriptionResponseSchema = FlexibleSchema(
    Schema.codable(
        OpenAITranscriptionResponse.self,
        jsonSchema: .object([
            "type": .string("object")
        ])
    )
)
