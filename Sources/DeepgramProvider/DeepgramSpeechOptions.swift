import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/deepgram/src/deepgram-speech-model.ts (provider options schema)
// Upstream commit: 73d5c5920e0fea7633027fdd87374adc9ba49743
//===----------------------------------------------------------------------===//

public struct DeepgramSpeechOptions: Sendable, Equatable {
    public enum BitRate: Sendable, Equatable {
        case number(Double)
        case string(String)
    }

    public enum CallbackMethod: String, Sendable, Equatable, Codable {
        case post = "POST"
        case put = "PUT"
    }

    public enum Tag: Sendable, Equatable {
        case single(String)
        case multiple([String])
    }

    public var bitRate: BitRate?
    public var container: String?
    public var encoding: String?
    public var sampleRate: Double?
    public var callback: String?
    public var callbackMethod: CallbackMethod?
    public var mipOptOut: Bool?
    public var tag: Tag?

    public init() {}
}

private let deepgramSpeechOptionsSchemaJSON: JSONValue = .object([
    "type": .string("object"),
    "additionalProperties": .bool(true)
])

public let deepgramSpeechOptionsSchema = FlexibleSchema(
    Schema<DeepgramSpeechOptions>(
        jsonSchemaResolver: { deepgramSpeechOptionsSchemaJSON },
        validator: { value in
            do {
                let json = try jsonValue(from: value)
                guard case .object(let dict) = json else {
                    let error = SchemaValidationIssuesError(vendor: "deepgram", issues: "provider options must be an object")
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                var options = DeepgramSpeechOptions()

                if let bitRateValue = dict["bitRate"], bitRateValue != .null {
                    switch bitRateValue {
                    case .number(let number):
                        options.bitRate = .number(number)
                    case .string(let string):
                        options.bitRate = .string(string)
                    default:
                        let error = SchemaValidationIssuesError(vendor: "deepgram", issues: "bitRate must be a number or string")
                        return .failure(error: TypeValidationError.wrap(value: bitRateValue, cause: error))
                    }
                }

                if let containerValue = dict["container"], containerValue != .null {
                    guard case .string(let container) = containerValue else {
                        let error = SchemaValidationIssuesError(vendor: "deepgram", issues: "container must be a string")
                        return .failure(error: TypeValidationError.wrap(value: containerValue, cause: error))
                    }
                    options.container = container
                }

                if let encodingValue = dict["encoding"], encodingValue != .null {
                    guard case .string(let encoding) = encodingValue else {
                        let error = SchemaValidationIssuesError(vendor: "deepgram", issues: "encoding must be a string")
                        return .failure(error: TypeValidationError.wrap(value: encodingValue, cause: error))
                    }
                    options.encoding = encoding
                }

                if let sampleRateValue = dict["sampleRate"], sampleRateValue != .null {
                    guard case .number(let sampleRate) = sampleRateValue else {
                        let error = SchemaValidationIssuesError(vendor: "deepgram", issues: "sampleRate must be a number")
                        return .failure(error: TypeValidationError.wrap(value: sampleRateValue, cause: error))
                    }
                    options.sampleRate = sampleRate
                }

                if let callbackValue = dict["callback"], callbackValue != .null {
                    guard case .string(let callback) = callbackValue else {
                        let error = SchemaValidationIssuesError(vendor: "deepgram", issues: "callback must be a string URL")
                        return .failure(error: TypeValidationError.wrap(value: callbackValue, cause: error))
                    }

                    guard let url = URL(string: callback), url.scheme != nil, url.host != nil else {
                        let error = SchemaValidationIssuesError(vendor: "deepgram", issues: "callback must be a valid URL")
                        return .failure(error: TypeValidationError.wrap(value: callbackValue, cause: error))
                    }
                    options.callback = callback
                }

                if let callbackMethodValue = dict["callbackMethod"], callbackMethodValue != .null {
                    guard case .string(let method) = callbackMethodValue,
                          let parsedMethod = DeepgramSpeechOptions.CallbackMethod(rawValue: method)
                    else {
                        let error = SchemaValidationIssuesError(vendor: "deepgram", issues: "callbackMethod must be POST or PUT")
                        return .failure(error: TypeValidationError.wrap(value: callbackMethodValue, cause: error))
                    }
                    options.callbackMethod = parsedMethod
                }

                if let mipOptOutValue = dict["mipOptOut"], mipOptOutValue != .null {
                    guard case .bool(let mipOptOut) = mipOptOutValue else {
                        let error = SchemaValidationIssuesError(vendor: "deepgram", issues: "mipOptOut must be a boolean")
                        return .failure(error: TypeValidationError.wrap(value: mipOptOutValue, cause: error))
                    }
                    options.mipOptOut = mipOptOut
                }

                if let tagValue = dict["tag"], tagValue != .null {
                    switch tagValue {
                    case .string(let tag):
                        options.tag = .single(tag)
                    case .array(let values):
                        var tags: [String] = []
                        for value in values {
                            guard case .string(let tag) = value else {
                                let error = SchemaValidationIssuesError(vendor: "deepgram", issues: "tag array must contain only strings")
                                return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                            }
                            tags.append(tag)
                        }
                        options.tag = .multiple(tags)
                    default:
                        let error = SchemaValidationIssuesError(vendor: "deepgram", issues: "tag must be a string or array of strings")
                        return .failure(error: TypeValidationError.wrap(value: tagValue, cause: error))
                    }
                }

                return .success(value: options)
            } catch {
                return .failure(error: TypeValidationError.wrap(value: value, cause: error))
            }
        }
    )
)
