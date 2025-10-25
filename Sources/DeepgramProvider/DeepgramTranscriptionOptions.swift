import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/deepgram/src/deepgram-transcription-model.ts (provider options schema)
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public struct DeepgramTranscriptionOptions: Sendable, Equatable {
    public enum SummarizeOption: Sendable, Equatable {
        case v2
        case disabled
    }

    public enum RedactOption: Sendable, Equatable {
        case single(String)
        case multiple([String])
    }

    public var language: String?
    public var smartFormat: Bool?
    public var punctuate: Bool?
    public var paragraphs: Bool?
    public var summarize: SummarizeOption?
    public var topics: Bool?
    public var intents: Bool?
    public var sentiment: Bool?
    public var detectEntities: Bool?
    public var redact: RedactOption?
    public var replace: String?
    public var search: String?
    public var keyterm: String?
    public var diarize: Bool?
    public var utterances: Bool?
    public var uttSplit: Double?
    public var fillerWords: Bool?

    public init() {}
}

private let deepgramTranscriptionOptionsSchemaJSON: JSONValue = .object([
    "type": .string("object"),
    "additionalProperties": .bool(true)
])

public let deepgramTranscriptionOptionsSchema = FlexibleSchema(
    Schema<DeepgramTranscriptionOptions>(
        jsonSchemaResolver: { deepgramTranscriptionOptionsSchemaJSON },
        validator: { value in
            do {
                let json = try jsonValue(from: value)
                guard case .object(let dict) = json else {
                    let error = SchemaValidationIssuesError(vendor: "deepgram", issues: "provider options must be an object")
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                var options = DeepgramTranscriptionOptions()

                if let languageValue = dict["language"], languageValue != .null {
                    guard case .string(let language) = languageValue else {
                        let error = SchemaValidationIssuesError(vendor: "deepgram", issues: "language must be a string")
                        return .failure(error: TypeValidationError.wrap(value: languageValue, cause: error))
                    }
                    options.language = language
                }

                if let smartFormatValue = dict["smartFormat"], smartFormatValue != .null {
                    guard case .bool(let flag) = smartFormatValue else {
                        let error = SchemaValidationIssuesError(vendor: "deepgram", issues: "smartFormat must be a boolean")
                        return .failure(error: TypeValidationError.wrap(value: smartFormatValue, cause: error))
                    }
                    options.smartFormat = flag
                }

                if let punctuateValue = dict["punctuate"], punctuateValue != .null {
                    guard case .bool(let flag) = punctuateValue else {
                        let error = SchemaValidationIssuesError(vendor: "deepgram", issues: "punctuate must be a boolean")
                        return .failure(error: TypeValidationError.wrap(value: punctuateValue, cause: error))
                    }
                    options.punctuate = flag
                }

                if let paragraphsValue = dict["paragraphs"], paragraphsValue != .null {
                    guard case .bool(let flag) = paragraphsValue else {
                        let error = SchemaValidationIssuesError(vendor: "deepgram", issues: "paragraphs must be a boolean")
                        return .failure(error: TypeValidationError.wrap(value: paragraphsValue, cause: error))
                    }
                    options.paragraphs = flag
                }

                if let summarizeValue = dict["summarize"], summarizeValue != .null {
                    switch summarizeValue {
                    case .string(let stringValue) where stringValue == "v2":
                        options.summarize = .v2
                    case .bool(let flag) where flag == false:
                        options.summarize = .disabled
                    default:
                        let error = SchemaValidationIssuesError(vendor: "deepgram", issues: "summarize must be 'v2' or false")
                        return .failure(error: TypeValidationError.wrap(value: summarizeValue, cause: error))
                    }
                }

                if let topicsValue = dict["topics"], topicsValue != .null {
                    guard case .bool(let flag) = topicsValue else {
                        let error = SchemaValidationIssuesError(vendor: "deepgram", issues: "topics must be a boolean")
                        return .failure(error: TypeValidationError.wrap(value: topicsValue, cause: error))
                    }
                    options.topics = flag
                }

                if let intentsValue = dict["intents"], intentsValue != .null {
                    guard case .bool(let flag) = intentsValue else {
                        let error = SchemaValidationIssuesError(vendor: "deepgram", issues: "intents must be a boolean")
                        return .failure(error: TypeValidationError.wrap(value: intentsValue, cause: error))
                    }
                    options.intents = flag
                }

                if let sentimentValue = dict["sentiment"], sentimentValue != .null {
                    guard case .bool(let flag) = sentimentValue else {
                        let error = SchemaValidationIssuesError(vendor: "deepgram", issues: "sentiment must be a boolean")
                        return .failure(error: TypeValidationError.wrap(value: sentimentValue, cause: error))
                    }
                    options.sentiment = flag
                }

                if let detectEntitiesValue = dict["detectEntities"], detectEntitiesValue != .null {
                    guard case .bool(let flag) = detectEntitiesValue else {
                        let error = SchemaValidationIssuesError(vendor: "deepgram", issues: "detectEntities must be a boolean")
                        return .failure(error: TypeValidationError.wrap(value: detectEntitiesValue, cause: error))
                    }
                    options.detectEntities = flag
                }

                if let redactValue = dict["redact"], redactValue != .null {
                    switch redactValue {
                    case .string(let value):
                        options.redact = .single(value)
                    case .array(let array):
                        var entries: [String] = []
                        for element in array {
                            guard case .string(let stringValue) = element else {
                                let error = SchemaValidationIssuesError(vendor: "deepgram", issues: "redact array must contain only strings")
                                return .failure(error: TypeValidationError.wrap(value: element, cause: error))
                            }
                            entries.append(stringValue)
                        }
                        options.redact = .multiple(entries)
                    default:
                        let error = SchemaValidationIssuesError(vendor: "deepgram", issues: "redact must be a string or array of strings")
                        return .failure(error: TypeValidationError.wrap(value: redactValue, cause: error))
                    }
                }

                if let replaceValue = dict["replace"], replaceValue != .null {
                    guard case .string(let replacement) = replaceValue else {
                        let error = SchemaValidationIssuesError(vendor: "deepgram", issues: "replace must be a string")
                        return .failure(error: TypeValidationError.wrap(value: replaceValue, cause: error))
                    }
                    options.replace = replacement
                }

                if let searchValue = dict["search"], searchValue != .null {
                    guard case .string(let search) = searchValue else {
                        let error = SchemaValidationIssuesError(vendor: "deepgram", issues: "search must be a string")
                        return .failure(error: TypeValidationError.wrap(value: searchValue, cause: error))
                    }
                    options.search = search
                }

                if let keytermValue = dict["keyterm"], keytermValue != .null {
                    guard case .string(let keyterm) = keytermValue else {
                        let error = SchemaValidationIssuesError(vendor: "deepgram", issues: "keyterm must be a string")
                        return .failure(error: TypeValidationError.wrap(value: keytermValue, cause: error))
                    }
                    options.keyterm = keyterm
                }

                if let diarizeValue = dict["diarize"], diarizeValue != .null {
                    guard case .bool(let flag) = diarizeValue else {
                        let error = SchemaValidationIssuesError(vendor: "deepgram", issues: "diarize must be a boolean")
                        return .failure(error: TypeValidationError.wrap(value: diarizeValue, cause: error))
                    }
                    options.diarize = flag
                }

                if let utterancesValue = dict["utterances"], utterancesValue != .null {
                    guard case .bool(let flag) = utterancesValue else {
                        let error = SchemaValidationIssuesError(vendor: "deepgram", issues: "utterances must be a boolean")
                        return .failure(error: TypeValidationError.wrap(value: utterancesValue, cause: error))
                    }
                    options.utterances = flag
                }

                if let uttSplitValue = dict["uttSplit"], uttSplitValue != .null {
                    guard case .number(let number) = uttSplitValue else {
                        let error = SchemaValidationIssuesError(vendor: "deepgram", issues: "uttSplit must be a number")
                        return .failure(error: TypeValidationError.wrap(value: uttSplitValue, cause: error))
                    }
                    options.uttSplit = number
                }

                if let fillerWordsValue = dict["fillerWords"], fillerWordsValue != .null {
                    guard case .bool(let flag) = fillerWordsValue else {
                        let error = SchemaValidationIssuesError(vendor: "deepgram", issues: "fillerWords must be a boolean")
                        return .failure(error: TypeValidationError.wrap(value: fillerWordsValue, cause: error))
                    }
                    options.fillerWords = flag
                }

                return .success(value: options)
            } catch {
                return .failure(error: TypeValidationError.wrap(value: value, cause: error))
            }
        }
    )
)
