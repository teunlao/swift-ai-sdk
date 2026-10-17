import AISDKProvider
import AISDKProviderUtils

public struct OpenAITranscriptionModelOptions: Sendable, Equatable {
    public var include: [String]?
    public var language: String?
    public var prompt: String?
    public var temperature: Double?
    public var timestampGranularities: [String]?
    public var responseFormat: String?
    public var chunkingStrategy: ChunkingStrategy?
    public var streaming: Streaming?

    public enum ChunkingStrategy: Sendable, Equatable {
        case auto
        case serverVAD(threshold: Double? = nil, prefixPaddingMs: Int? = nil, silenceDurationMs: Int? = nil)
    }

    public struct Streaming: Sendable, Equatable {
        public var delay: String?
        public var include: [String]?

        public init(delay: String? = nil, include: [String]? = nil) {
            self.delay = delay
            self.include = include
        }
    }

    public init(
        include: [String]? = nil,
        language: String? = nil,
        prompt: String? = nil,
        temperature: Double? = nil,
        timestampGranularities: [String]? = nil,
        responseFormat: String? = nil,
        chunkingStrategy: ChunkingStrategy? = nil,
        streaming: Streaming? = nil
    ) {
        self.include = include
        self.language = language
        self.prompt = prompt
        self.temperature = temperature
        self.timestampGranularities = timestampGranularities
        self.responseFormat = responseFormat
        self.chunkingStrategy = chunkingStrategy
        self.streaming = streaming
    }
}

public let openAITranscriptionModelOptionsSchema = FlexibleSchema<OpenAITranscriptionModelOptions>(Schema(
    jsonSchemaResolver: { TranscriptionOptionsParser.jsonSchema },
    validator: { value in
        do { return .success(value: try TranscriptionOptionsParser.parse(jsonValue(from: value))) }
        catch { return .failure(error: TypeValidationError.wrap(value: value, cause: error)) }
    }
))

private enum TranscriptionOptionsParser {
    static let jsonSchema: JSONValue = {
        let string: JSONValue = ["type": "string"]
        let strings: JSONValue = ["type": "array", "items": string]
        let ratio: JSONValue = ["type": "number", "minimum": 0, "maximum": 1]
        let milliseconds: JSONValue = ["type": "integer", "minimum": 0, "maximum": .number(maxMilliseconds)]
        return [
            "type": "object", "additionalProperties": false,
            "properties": [
                "include": strings, "language": string, "prompt": string,
                "temperature": ["type": "number", "minimum": 0, "maximum": 1, "default": 0],
                "timestampGranularities": ["type": "array", "items": ["enum": ["word", "segment"]], "default": ["segment"]],
                "responseFormat": ["enum": ["json", "verbose_json", "diarized_json"]],
                "chunkingStrategy": ["anyOf": [
                    ["const": "auto"],
                    ["type": "object", "required": ["type"], "additionalProperties": false, "properties": [
                        "type": ["const": "server_vad"], "threshold": ratio,
                        "prefixPaddingMs": milliseconds, "silenceDurationMs": milliseconds
                    ]]
                ]],
                "streaming": ["type": "object", "additionalProperties": false, "properties": [
                    "delay": ["enum": ["minimal", "low", "medium", "high", "xhigh"]], "include": strings
                ]]
            ]
        ]
    }()

    static func parse(_ value: JSONValue) throws -> OpenAITranscriptionModelOptions {
        guard case .object(let object) = value else { throw invalid("expected object") }
        var result = OpenAITranscriptionModelOptions(
            include: try strings(object["include"]),
            language: try string(object["language"]),
            prompt: try string(object["prompt"]),
            temperature: try ratio(object["temperature"]) ?? 0,
            timestampGranularities: try strings(object["timestampGranularities"], allowed: ["word", "segment"]) ?? ["segment"],
            responseFormat: try string(object["responseFormat"], allowed: ["json", "verbose_json", "diarized_json"])
        )
        if let chunking = object["chunkingStrategy"] {
            if chunking == "auto" {
                result.chunkingStrategy = .auto
            } else if case .object(let vad) = chunking, vad["type"] == "server_vad" {
                result.chunkingStrategy = .serverVAD(
                    threshold: try ratio(vad["threshold"]),
                    prefixPaddingMs: try milliseconds(vad["prefixPaddingMs"]),
                    silenceDurationMs: try milliseconds(vad["silenceDurationMs"])
                )
            } else { throw invalid("invalid chunkingStrategy") }
        }
        if let streaming = object["streaming"] {
            guard case .object(let object) = streaming else { throw invalid("streaming must be an object") }
            result.streaming = .init(
                delay: try string(object["delay"], allowed: ["minimal", "low", "medium", "high", "xhigh"]),
                include: try strings(object["include"])
            )
        }
        return result
    }

    private static func string(_ value: JSONValue?, allowed: [String]? = nil) throws -> String? {
        guard let value else { return nil }
        guard case .string(let text) = value, allowed?.contains(text) ?? true else { throw invalid("invalid string option") }
        return text
    }

    private static func strings(_ value: JSONValue?, allowed: [String]? = nil) throws -> [String]? {
        guard let value else { return nil }
        guard case .array(let array) = value else { throw invalid("expected array") }
        return try array.map { try string($0, allowed: allowed)! }
    }

    private static func ratio(_ value: JSONValue?) throws -> Double? {
        guard let value else { return nil }
        guard case .number(let number) = value, number.isFinite, (0...1).contains(number) else { throw invalid("expected a number between 0 and 1") }
        return number
    }

    // Zod v4 int validates safe integers, independently of Swift's Int width.
    private static let maxMilliseconds: Double = 9_007_199_254_740_991

    private static func milliseconds(_ value: JSONValue?) throws -> Int? {
        guard let value else { return nil }
        guard case .number(let number) = value, (0...maxMilliseconds).contains(number), let integer = Int(exactly: number) else { throw invalid("expected non-negative safe integer milliseconds") }
        return integer
    }

    private static func invalid(_ message: String) -> SchemaValidationIssuesError {
        SchemaValidationIssuesError(vendor: "openai", issues: message)
    }
}
