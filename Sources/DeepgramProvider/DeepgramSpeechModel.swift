import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/deepgram/src/deepgram-speech-model.ts
// Upstream commit: 73d5c5920e0fea7633027fdd87374adc9ba49743
//===----------------------------------------------------------------------===//

public final class DeepgramSpeechModel: SpeechModelV3 {
    public struct Config: Sendable {
        public struct RequestOptions: Sendable {
            public let modelId: DeepgramSpeechModelId
            public let path: String

            public init(modelId: DeepgramSpeechModelId, path: String) {
                self.modelId = modelId
                self.path = path
            }
        }

        public let provider: String
        public let url: @Sendable (RequestOptions) -> String
        public let headers: @Sendable () -> [String: String?]
        public let fetch: FetchFunction?
        public let currentDate: @Sendable () -> Date

        public init(
            provider: String,
            url: @escaping @Sendable (RequestOptions) -> String,
            headers: @escaping @Sendable () -> [String: String?],
            fetch: FetchFunction?,
            currentDate: @escaping @Sendable () -> Date = { Date() }
        ) {
            self.provider = provider
            self.url = url
            self.headers = headers
            self.fetch = fetch
            self.currentDate = currentDate
        }
    }

    private struct PreparedArgs {
        let requestBody: RequestBody
        var queryParams: [String: String]
        var warnings: [SharedV3Warning]
    }

    private struct RequestBody: Codable, Sendable, Equatable {
        let text: String
    }

    private struct FormatMapping {
        let encoding: String?
        let container: String?
        let sampleRate: Int?
        let bitRate: Int?
    }

    private let modelIdentifier: DeepgramSpeechModelId
    private let config: Config

    init(modelId: DeepgramSpeechModelId, config: Config) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }

    public func doGenerate(options: SpeechModelV3CallOptions) async throws -> SpeechModelV3Result {
        let now = config.currentDate()
        let prepared = try await getArgs(options: options)

        let baseUrl = config.url(.init(modelId: modelIdentifier, path: "/v1/speak"))
        let url = Self.appendQueryParams(baseUrl: baseUrl, queryParams: prepared.queryParams)

        let headers = combineHeaders(
            config.headers(),
            options.headers?.mapValues { Optional($0) }
        ).compactMapValues { $0 }

        let response = try await postJsonToAPI(
            url: url,
            headers: headers,
            body: prepared.requestBody,
            failedResponseHandler: deepgramFailedResponseHandler,
            successfulResponseHandler: createBinaryResponseHandler(),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let requestBodyString: String? = {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.withoutEscapingSlashes]
            guard let data = try? encoder.encode(prepared.requestBody) else { return nil }
            return String(data: data, encoding: .utf8)
        }()

        return SpeechModelV3Result(
            audio: .binary(response.value),
            warnings: prepared.warnings,
            request: .init(body: requestBodyString),
            response: .init(
                timestamp: now,
                modelId: modelIdentifier.rawValue,
                headers: response.responseHeaders,
                body: response.rawValue
            )
        )
    }

    private func getArgs(options: SpeechModelV3CallOptions) async throws -> PreparedArgs {
        var warnings: [SharedV3Warning] = []

        let deepgramOptions = try await parseProviderOptions(
            provider: "deepgram",
            providerOptions: options.providerOptions,
            schema: deepgramSpeechOptionsSchema
        )

        let requestBody = RequestBody(text: options.text)

        var queryParams: [String: String] = [
            "model": modelIdentifier.rawValue
        ]

        // Map outputFormat to encoding/container/sample_rate/bit_rate
        let outputFormat = (options.outputFormat ?? "mp3")
        let formatLower = outputFormat.lowercased()

        let formatMap: [String: FormatMapping] = [
            "mp3": .init(encoding: "mp3", container: nil, sampleRate: nil, bitRate: nil),
            "wav": .init(encoding: "linear16", container: "wav", sampleRate: nil, bitRate: nil),
            "linear16": .init(encoding: "linear16", container: "wav", sampleRate: nil, bitRate: nil),
            "mulaw": .init(encoding: "mulaw", container: "wav", sampleRate: nil, bitRate: nil),
            "alaw": .init(encoding: "alaw", container: "wav", sampleRate: nil, bitRate: nil),
            "opus": .init(encoding: "opus", container: "ogg", sampleRate: nil, bitRate: nil),
            "ogg": .init(encoding: "opus", container: "ogg", sampleRate: nil, bitRate: nil),
            "flac": .init(encoding: "flac", container: nil, sampleRate: nil, bitRate: nil),
            "aac": .init(encoding: "aac", container: nil, sampleRate: nil, bitRate: nil),
            "pcm": .init(encoding: "linear16", container: "none", sampleRate: nil, bitRate: nil)
        ]

        if let mapped = formatMap[formatLower] {
            if let encoding = mapped.encoding {
                queryParams["encoding"] = encoding
            }
            if let container = mapped.container {
                queryParams["container"] = container
            }
            if let sampleRate = mapped.sampleRate {
                queryParams["sample_rate"] = String(sampleRate)
            }
            if let bitRate = mapped.bitRate {
                queryParams["bit_rate"] = String(bitRate)
            }
        } else {
            // Try to parse format like "wav_44100" or "linear16_24000"
            let parts = formatLower.split(separator: "_", omittingEmptySubsequences: true)
            if parts.count >= 2 {
                let firstPart = String(parts[0])
                let secondPart = String(parts[1])
                let sampleRate = Int(secondPart)

                let knownEncodings: Set<String> = [
                    "linear16",
                    "mulaw",
                    "alaw",
                    "mp3",
                    "opus",
                    "flac",
                    "aac"
                ]

                if knownEncodings.contains(firstPart) {
                    queryParams["encoding"] = firstPart

                    if ["linear16", "mulaw", "alaw"].contains(firstPart) {
                        queryParams["container"] = "wav"
                    } else if firstPart == "opus" {
                        queryParams["container"] = "ogg"
                    }

                    if let sampleRate {
                        if firstPart == "linear16" && [8000, 16000, 24000, 32000, 48000].contains(sampleRate) {
                            queryParams["sample_rate"] = String(sampleRate)
                        } else if firstPart == "mulaw" && [8000, 16000].contains(sampleRate) {
                            queryParams["sample_rate"] = String(sampleRate)
                        } else if firstPart == "alaw" && [8000, 16000].contains(sampleRate) {
                            queryParams["sample_rate"] = String(sampleRate)
                        } else if firstPart == "flac" && [8000, 16000, 22050, 32000, 48000].contains(sampleRate) {
                            queryParams["sample_rate"] = String(sampleRate)
                        }
                        // mp3, opus, aac have fixed sample rates, don't set.
                    }
                } else if ["wav", "ogg"].contains(firstPart) {
                    if firstPart == "wav" {
                        queryParams["container"] = "wav"
                        queryParams["encoding"] = "linear16"
                    } else if firstPart == "ogg" {
                        queryParams["container"] = "ogg"
                        queryParams["encoding"] = "opus"
                    }

                    if let sampleRate {
                        queryParams["sample_rate"] = String(sampleRate)
                    }
                }
            }
        }

        // Provider options mapping + validation
        if let deepgramOptions {
            if let encoding = deepgramOptions.encoding {
                let newEncoding = encoding.lowercased()
                queryParams["encoding"] = newEncoding

                if let container = deepgramOptions.container {
                    let containerLower = container.lowercased()

                    if ["linear16", "mulaw", "alaw"].contains(newEncoding) {
                        if !["wav", "none"].contains(containerLower) {
                            warnings.append(
                                .unsupported(
                                    feature: "providerOptions",
                                    details: "Encoding \"\(newEncoding)\" only supports containers \"wav\" or \"none\". Container \"\(container)\" was ignored."
                                )
                            )
                        } else {
                            queryParams["container"] = containerLower
                        }
                    } else if newEncoding == "opus" {
                        queryParams["container"] = "ogg"
                    } else if ["mp3", "flac", "aac"].contains(newEncoding) {
                        warnings.append(
                            .unsupported(
                                feature: "providerOptions",
                                details: "Encoding \"\(newEncoding)\" does not support container parameter. Container \"\(container)\" was ignored."
                            )
                        )
                        queryParams.removeValue(forKey: "container")
                    }
                } else {
                    if ["mp3", "flac", "aac"].contains(newEncoding) {
                        queryParams.removeValue(forKey: "container")
                    } else if ["linear16", "mulaw", "alaw"].contains(newEncoding) {
                        if queryParams["container"] == nil {
                            queryParams["container"] = "wav"
                        }
                    } else if newEncoding == "opus" {
                        queryParams["container"] = "ogg"
                    }
                }

                // Clean up incompatible parameters when encoding changes
                if ["mp3", "opus", "aac"].contains(newEncoding) {
                    queryParams.removeValue(forKey: "sample_rate")
                }
                if ["linear16", "mulaw", "alaw", "flac"].contains(newEncoding) {
                    queryParams.removeValue(forKey: "bit_rate")
                }
            } else if let container = deepgramOptions.container {
                let containerLower = container.lowercased()
                let oldEncoding = queryParams["encoding"]?.lowercased()
                var newEncoding: String?

                if containerLower == "wav" {
                    queryParams["container"] = "wav"
                    newEncoding = "linear16"
                } else if containerLower == "ogg" {
                    queryParams["container"] = "ogg"
                    newEncoding = "opus"
                } else if containerLower == "none" {
                    queryParams["container"] = "none"
                    newEncoding = "linear16"
                }

                if let newEncoding, newEncoding != oldEncoding {
                    queryParams["encoding"] = newEncoding

                    if ["mp3", "opus", "aac"].contains(newEncoding) {
                        queryParams.removeValue(forKey: "sample_rate")
                    }
                    if ["linear16", "mulaw", "alaw", "flac"].contains(newEncoding) {
                        queryParams.removeValue(forKey: "bit_rate")
                    }
                }
            }

            if let sampleRate = deepgramOptions.sampleRate {
                let encoding = queryParams["encoding"]?.lowercased() ?? ""
                let sampleRateString = Self.jsNumberString(sampleRate)

                if encoding == "linear16" {
                    let allowed: [Double] = [8000, 16000, 24000, 32000, 48000]
                    if !allowed.contains(sampleRate) {
                        warnings.append(
                            .unsupported(
                                feature: "providerOptions",
                                details: "Encoding \"linear16\" only supports sample rates: 8000, 16000, 24000, 32000, 48000. Sample rate \(sampleRateString) was ignored."
                            )
                        )
                    } else {
                        queryParams["sample_rate"] = sampleRateString
                    }
                } else if encoding == "mulaw" || encoding == "alaw" {
                    let allowed: [Double] = [8000, 16000]
                    if !allowed.contains(sampleRate) {
                        warnings.append(
                            .unsupported(
                                feature: "providerOptions",
                                details: "Encoding \"\(encoding)\" only supports sample rates: 8000, 16000. Sample rate \(sampleRateString) was ignored."
                            )
                        )
                    } else {
                        queryParams["sample_rate"] = sampleRateString
                    }
                } else if encoding == "flac" {
                    let allowed: [Double] = [8000, 16000, 22050, 32000, 48000]
                    if !allowed.contains(sampleRate) {
                        warnings.append(
                            .unsupported(
                                feature: "providerOptions",
                                details: "Encoding \"flac\" only supports sample rates: 8000, 16000, 22050, 32000, 48000. Sample rate \(sampleRateString) was ignored."
                            )
                        )
                    } else {
                        queryParams["sample_rate"] = sampleRateString
                    }
                } else if ["mp3", "opus", "aac"].contains(encoding) {
                    warnings.append(
                        .unsupported(
                            feature: "providerOptions",
                            details: "Encoding \"\(encoding)\" has a fixed sample rate and does not support sample_rate parameter. Sample rate \(sampleRateString) was ignored."
                        )
                    )
                } else {
                    queryParams["sample_rate"] = sampleRateString
                }
            }

            if let bitRate = deepgramOptions.bitRate {
                let encoding = queryParams["encoding"]?.lowercased() ?? ""

                let bitRateString: String
                let bitRateNumber: Double?
                switch bitRate {
                case .number(let number):
                    bitRateString = Self.jsNumberString(number)
                    bitRateNumber = number
                case .string(let string):
                    bitRateString = string
                    bitRateNumber = Double(string)
                }

                if encoding == "mp3" {
                    let allowed: [Double] = [32000, 48000]
                    if bitRateNumber == nil || !allowed.contains(bitRateNumber!) {
                        warnings.append(
                            .unsupported(
                                feature: "providerOptions",
                                details: "Encoding \"mp3\" only supports bit rates: 32000, 48000. Bit rate \(bitRateString) was ignored."
                            )
                        )
                    } else {
                        queryParams["bit_rate"] = bitRateString
                    }
                } else if encoding == "opus" {
                    if bitRateNumber == nil || bitRateNumber! < 4000 || bitRateNumber! > 650_000 {
                        warnings.append(
                            .unsupported(
                                feature: "providerOptions",
                                details: "Encoding \"opus\" supports bit rates between 4000 and 650000. Bit rate \(bitRateString) was ignored."
                            )
                        )
                    } else {
                        queryParams["bit_rate"] = bitRateString
                    }
                } else if encoding == "aac" {
                    if bitRateNumber == nil || bitRateNumber! < 4000 || bitRateNumber! > 192_000 {
                        warnings.append(
                            .unsupported(
                                feature: "providerOptions",
                                details: "Encoding \"aac\" supports bit rates between 4000 and 192000. Bit rate \(bitRateString) was ignored."
                            )
                        )
                    } else {
                        queryParams["bit_rate"] = bitRateString
                    }
                } else if ["linear16", "mulaw", "alaw", "flac"].contains(encoding) {
                    warnings.append(
                        .unsupported(
                            feature: "providerOptions",
                            details: "Encoding \"\(encoding)\" does not support bit_rate parameter. Bit rate \(bitRateString) was ignored."
                        )
                    )
                } else {
                    queryParams["bit_rate"] = bitRateString
                }
            }

            if let callback = deepgramOptions.callback {
                queryParams["callback"] = callback
            }
            if let callbackMethod = deepgramOptions.callbackMethod {
                queryParams["callback_method"] = callbackMethod.rawValue
            }
            if let mipOptOut = deepgramOptions.mipOptOut {
                queryParams["mip_opt_out"] = mipOptOut ? "true" : "false"
            }
            if let tag = deepgramOptions.tag {
                switch tag {
                case .single(let value):
                    queryParams["tag"] = value
                case .multiple(let values):
                    queryParams["tag"] = values.joined(separator: ",")
                }
            }
        }

        // Warnings for parameters unsupported by Deepgram's TTS REST API.
        if let voice = options.voice, !voice.isEmpty, voice != modelIdentifier.rawValue {
            warnings.append(
                .unsupported(
                    feature: "voice",
                    details: "Deepgram TTS models embed the voice in the model ID. The voice parameter \"\(voice)\" was ignored. Use the model ID to select a voice (e.g., \"aura-2-helena-en\")."
                )
            )
        }

        if options.speed != nil {
            warnings.append(
                .unsupported(
                    feature: "speed",
                    details: "Deepgram TTS REST API does not support speed adjustment. Speed parameter was ignored."
                )
            )
        }

        if let language = options.language, !language.isEmpty {
            warnings.append(
                .unsupported(
                    feature: "language",
                    details: "Deepgram TTS models are language-specific via the model ID. Language parameter \"\(language)\" was ignored. Select a model with the appropriate language suffix (e.g., \"-en\" for English)."
                )
            )
        }

        if let instructions = options.instructions, !instructions.isEmpty {
            warnings.append(
                .unsupported(
                    feature: "instructions",
                    details: "Deepgram TTS REST API does not support instructions. Instructions parameter was ignored."
                )
            )
        }

        return PreparedArgs(
            requestBody: requestBody,
            queryParams: queryParams,
            warnings: warnings
        )
    }

    private static func appendQueryParams(baseUrl: String, queryParams: [String: String]) -> String {
        guard !queryParams.isEmpty else { return baseUrl }

        if var components = URLComponents(string: baseUrl) {
            components.queryItems = queryParams.map { URLQueryItem(name: $0.key, value: $0.value) }
            if let url = components.url?.absoluteString {
                return url
            }
        }

        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=?")
        let encoded = queryParams.compactMap { key, value -> String? in
            guard let keyEncoded = key.addingPercentEncoding(withAllowedCharacters: allowed),
                  let valueEncoded = value.addingPercentEncoding(withAllowedCharacters: allowed) else {
                return nil
            }
            return "\(keyEncoded)=\(valueEncoded)"
        }
        let queryString = encoded.joined(separator: "&")
        return queryString.isEmpty ? baseUrl : "\(baseUrl)?\(queryString)"
    }

    private static func jsNumberString(_ value: Double) -> String {
        // Match JavaScript number -> string behavior for integers in messages/query params.
        if value.isFinite, value.rounded(.towardZero) == value {
            return String(Int(value))
        }
        return String(value)
    }
}
