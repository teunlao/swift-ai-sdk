import AISDKProvider
import AISDKProviderUtils

struct OpenAITranscriptionResponse: Decodable, Sendable {
    struct Word: Decodable, Sendable {
        let word: String
        let start: Double
        let end: Double
    }

    struct VerboseSegment: Decodable, Sendable {
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
            case id, seek, start, end, text, tokens, temperature
            case avgLogprob = "avg_logprob"
            case compressionRatio = "compression_ratio"
            case noSpeechProb = "no_speech_prob"
        }
    }

    struct DiarizedSegment: Decodable, Sendable {
        let type: String
        let id: String
        let start: Double
        let end: Double
        let text: String
        let speaker: String
    }

    enum Segment: Decodable, Sendable {
        case verbose(VerboseSegment)
        case diarized(DiarizedSegment)

        init(from decoder: any Decoder) throws {
            if let segment = try? VerboseSegment(from: decoder) {
                self = .verbose(segment)
            } else {
                let segment = try DiarizedSegment(from: decoder)
                guard segment.type == "transcript.text.segment" else {
                    throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid diarized segment type"))
                }
                self = .diarized(segment)
            }
        }

        var text: String {
            switch self { case .verbose(let value): value.text; case .diarized(let value): value.text }
        }
        var start: Double {
            switch self { case .verbose(let value): value.start; case .diarized(let value): value.start }
        }
        var end: Double {
            switch self { case .verbose(let value): value.end; case .diarized(let value): value.end }
        }
    }

    let text: String
    let language: String?
    let duration: Double?
    let words: [Word]?
    let segments: [Segment]?
    let usage: JSONObject?
}

let openAITranscriptionResponseSchema = FlexibleSchema(Schema.codable(
    OpenAITranscriptionResponse.self,
    jsonSchema: ["type": "object"]
))
