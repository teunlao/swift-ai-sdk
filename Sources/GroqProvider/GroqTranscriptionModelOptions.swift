import Foundation
import AISDKProviderUtils

public struct GroqTranscriptionModelOptions: Codable, Sendable, Equatable {
    public let language: String?
    public let prompt: String?
    public let responseFormat: String?
    public let temperature: Double?
    public let timestampGranularities: [String]?

    public init(
        language: String? = nil,
        prompt: String? = nil,
        responseFormat: String? = nil,
        temperature: Double? = nil,
        timestampGranularities: [String]? = nil
    ) throws {
        if let temperature, !temperature.isFinite || !(0...1).contains(temperature) {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "temperature must be between 0 and 1"))
        }
        self.language = language
        self.prompt = prompt
        self.responseFormat = responseFormat
        self.temperature = temperature
        self.timestampGranularities = timestampGranularities
    }

    private enum CodingKeys: String, CodingKey {
        case language, prompt, responseFormat, temperature, timestampGranularities
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            language: container.decodeIfPresent(String.self, forKey: .language),
            prompt: container.decodeIfPresent(String.self, forKey: .prompt),
            responseFormat: container.decodeIfPresent(String.self, forKey: .responseFormat),
            temperature: container.decodeIfPresent(Double.self, forKey: .temperature),
            timestampGranularities: container.decodeIfPresent([String].self, forKey: .timestampGranularities)
        )
    }
}

let groqTranscriptionModelOptions = FlexibleSchema(
    Schema<GroqTranscriptionModelOptions>.codable(GroqTranscriptionModelOptions.self, jsonSchema: ["type": "object"])
)
