import Foundation
import AISDKProvider
import AISDKProviderUtils

public final class OpenAITranscriptionModel: TranscriptionModelV3, TranscriptionModelV4Streaming {
    private let modelIdentifier: OpenAITranscriptionModelId
    private let config: OpenAIConfig

    public init(modelId: OpenAITranscriptionModelId, config: OpenAIConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }

    public func doGenerate(options: TranscriptionModelV3CallOptions) async throws -> TranscriptionModelV3Result {
        if isRealtimeTranscriptionModelId(modelIdentifier.rawValue) {
            throw UnsupportedFunctionalityError(functionality: "non-streaming transcription with \(modelIdentifier.rawValue)")
        }

        let prepared = try await prepareRequest(options: options)

        var headers = combineHeaders(try config.headers(), options.headers?.mapValues { Optional($0) })
            .compactMapValues { $0 }
        headers["Content-Type"] = prepared.contentType

        let response = try await postToAPI(
            url: config.url(.init(modelId: modelIdentifier.rawValue, path: "/audio/transcriptions")),
            headers: headers,
            body: PostBody(content: .data(prepared.body), values: nil),
            failedResponseHandler: openAIFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: openAITranscriptionResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let currentDate = config._internal?.currentDate?() ?? Date()
        let result = mapResponse(response.value)

        return TranscriptionModelV3Result(
            text: result.text,
            segments: result.segments,
            language: result.language,
            durationInSeconds: result.duration,
            warnings: prepared.warnings,
            request: nil,
            response: TranscriptionModelV3Result.ResponseInfo(
                timestamp: currentDate,
                modelId: modelIdentifier.rawValue,
                headers: response.responseHeaders,
                body: response.rawValue
            ),
            providerMetadata: nil
        )
    }

    public func doGenerate(options: TranscriptionModelV4CallOptions) async throws -> TranscriptionModelV4Result {
        let result = try await doGenerate(
            options: TranscriptionModelV3CallOptions(
                audio: v3Audio(from: options.audio),
                mediaType: options.mediaType,
                providerOptions: options.providerOptions,
                abortSignal: options.abortSignal,
                headers: options.headers
            )
        )

        return TranscriptionModelV4Result(
            text: result.text,
            segments: result.segments.map {
                TranscriptionModelV4Result.Segment(
                    text: $0.text,
                    startSecond: $0.startSecond,
                    endSecond: $0.endSecond
                )
            },
            language: result.language,
            durationInSeconds: result.durationInSeconds,
            warnings: result.warnings.map(convertSharedV3WarningToV4),
            request: result.request.map { TranscriptionModelV4Result.RequestInfo(body: $0.body) },
            response: TranscriptionModelV4Result.ResponseInfo(
                timestamp: result.response.timestamp,
                modelId: result.response.modelId,
                headers: result.response.headers,
                body: result.response.body
            ),
            providerMetadata: result.providerMetadata
        )
    }

    public func doStream(options: TranscriptionModelV4StreamOptions) async throws -> TranscriptionModelV4StreamResult {
        if !isRealtimeTranscriptionModelId(modelIdentifier.rawValue) {
            throw UnsupportedFunctionalityError(functionality: "streaming transcription with \(modelIdentifier.rawValue)")
        }

        let currentDate = config._internal?.currentDate?() ?? Date()
        let openAIOptions = try await parseProviderOptions(
            provider: "openai",
            providerOptions: options.providerOptions,
            schema: openAITranscriptionProviderOptionsSchema
        )

        let warnings = streamingWarnings(from: options.providerOptions?["openai"] ?? [:])
        let headers = combineHeaders(try config.headers(), options.headers?.mapValues { Optional($0) })
            .compactMapValues { $0 }
        let sessionUpdate = buildRealtimeTranscriptionSession(
            modelId: modelIdentifier.rawValue,
            inputAudioFormat: options.inputAudioFormat,
            providerOptions: openAIOptions
        )
        let webSocketURL = try makeWebSocketURL(
            from: config.url(.init(modelId: modelIdentifier.rawValue, path: "/realtime?intent=transcription"))
        )

        return TranscriptionModelV4StreamResult(
            stream: createRealtimeTranscriptionStream(
                webSocketFactory: config.webSocket ?? makeDefaultOpenAIWebSocketConnection,
                request: OpenAIWebSocketRequest(
                    url: webSocketURL,
                    protocols: openAIRealtimeProtocols(headers: headers),
                    headers: headers
                ),
                sessionUpdate: sessionUpdate,
                language: openAIOptions?.language,
                warnings: warnings,
                audio: options.audio,
                abortSignal: options.abortSignal,
                includeRawChunks: options.includeRawChunks ?? false
            ),
            request: TranscriptionModelV4StreamResult.RequestInfo(body: sessionUpdate),
            response: TranscriptionModelV4StreamResult.ResponseInfo(
                timestamp: currentDate,
                modelId: modelIdentifier.rawValue
            )
        )
    }

    // MARK: - Preparation

    private struct PreparedRequest {
        let body: Data
        let contentType: String
        let warnings: [SharedV3Warning]
    }

    private func prepareRequest(options: TranscriptionModelV3CallOptions) async throws -> PreparedRequest {
        let warnings: [SharedV3Warning] = []

        let openAIOptions = try await parseProviderOptions(
            provider: "openai",
            providerOptions: options.providerOptions,
            schema: openAITranscriptionProviderOptionsSchema
        )

        let audioData = try data(from: options.audio)
        let fileExtension = mediaTypeToExtension(options.mediaType)
        let filename = fileExtension.isEmpty ? "audio" : "audio.\(fileExtension)"

        var builder = MultipartFormDataBuilder()
        builder.appendField(name: "model", value: modelIdentifier.rawValue)
        builder.appendFile(name: "file", filename: filename, contentType: options.mediaType, data: audioData)

        if let openAIOptions {
            if let include = openAIOptions.include {
                for value in include {
                    builder.appendField(name: "include[]", value: value)
                }
            }
            if let language = openAIOptions.language {
                builder.appendField(name: "language", value: language)
            }
            if let prompt = openAIOptions.prompt {
                builder.appendField(name: "prompt", value: prompt)
            }

            builder.appendField(name: "response_format", value: responseFormat(for: modelIdentifier))

            if let temperature = openAIOptions.temperature {
                builder.appendField(name: "temperature", value: String(temperature))
            }
            if let granularities = openAIOptions.timestampGranularities {
                for granularity in granularities {
                    builder.appendField(name: "timestamp_granularities[]", value: granularity)
                }
            }
        }

        let (body, contentType) = builder.build()
        return PreparedRequest(body: body, contentType: contentType, warnings: warnings)
    }

    private func data(from audio: TranscriptionModelV3Audio) throws -> Data {
        switch audio {
        case .binary(let data):
            return data
        case .base64(let base64):
            return try convertBase64ToData(base64)
        }
    }

    private func responseFormat(for modelId: OpenAITranscriptionModelId) -> String {
        switch modelId.rawValue {
        case "gpt-4o-transcribe", "gpt-4o-mini-transcribe":
            return "json"
        default:
            return "verbose_json"
        }
    }

    // MARK: - Response Mapping

    private struct MappedResponse {
        let text: String
        let segments: [TranscriptionModelV3Result.Segment]
        let language: String?
        let duration: Double?
    }

    private func mapResponse(_ response: OpenAITranscriptionResponse) -> MappedResponse {
        let languageCode = response.language.flatMap { languageLookup[$0] }

        let segments: [TranscriptionModelV3Result.Segment]
        if let responseSegments = response.segments {
            segments = responseSegments.map {
                TranscriptionModelV3Result.Segment(
                    text: $0.text,
                    startSecond: $0.start,
                    endSecond: $0.end
                )
            }
        } else if let words = response.words {
            segments = words.map {
                TranscriptionModelV3Result.Segment(
                    text: $0.word,
                    startSecond: $0.start,
                    endSecond: $0.end
                )
            }
        } else {
            segments = []
        }

        return MappedResponse(
            text: response.text,
            segments: segments,
            language: languageCode,
            duration: response.duration
        )
    }

    private let languageLookup: [String: String] = [
        "afrikaans": "af",
        "arabic": "ar",
        "armenian": "hy",
        "azerbaijani": "az",
        "belarusian": "be",
        "bosnian": "bs",
        "bulgarian": "bg",
        "catalan": "ca",
        "chinese": "zh",
        "croatian": "hr",
        "czech": "cs",
        "danish": "da",
        "dutch": "nl",
        "english": "en",
        "estonian": "et",
        "finnish": "fi",
        "french": "fr",
        "galician": "gl",
        "german": "de",
        "greek": "el",
        "hebrew": "he",
        "hindi": "hi",
        "hungarian": "hu",
        "icelandic": "is",
        "indonesian": "id",
        "italian": "it",
        "japanese": "ja",
        "kannada": "kn",
        "kazakh": "kk",
        "korean": "ko",
        "latvian": "lv",
        "lithuanian": "lt",
        "macedonian": "mk",
        "malay": "ms",
        "marathi": "mr",
        "maori": "mi",
        "nepali": "ne",
        "norwegian": "no",
        "persian": "fa",
        "polish": "pl",
        "portuguese": "pt",
        "romanian": "ro",
        "russian": "ru",
        "serbian": "sr",
        "slovak": "sk",
        "slovenian": "sl",
        "spanish": "es",
        "swahili": "sw",
        "swedish": "sv",
        "tagalog": "tl",
        "tamil": "ta",
        "thai": "th",
        "turkish": "tr",
        "ukrainian": "uk",
        "urdu": "ur",
        "vietnamese": "vi",
        "welsh": "cy"
    ]
}

private func isRealtimeTranscriptionModelId(_ modelId: String) -> Bool {
    modelId == "gpt-realtime-whisper" || modelId.hasPrefix("gpt-realtime-whisper-")
}

private func v3Audio(from audio: TranscriptionModelV4Audio) -> TranscriptionModelV3Audio {
    switch audio {
    case .binary(let data):
        return .binary(data)
    case .base64(let base64):
        return .base64(base64)
    }
}

private func convertSharedV3WarningToV4(_ warning: SharedV3Warning) -> SharedV4Warning {
    switch warning {
    case let .unsupported(feature, details):
        return .unsupported(feature: feature, details: details)
    case let .compatibility(feature, details):
        return .compatibility(feature: feature, details: details)
    case let .other(message):
        return .other(message: message)
    }
}

private func streamingWarnings(from rawOpenAIOptions: JSONObject) -> [SharedV4Warning] {
    ["include", "prompt", "temperature", "timestampGranularities"].compactMap { option in
        guard let value = rawOpenAIOptions[option], value != .null else {
            return nil
        }
        return .unsupported(
            feature: "providerOptions.openai.\(option)",
            details: "OpenAI streaming transcription does not support \(option)."
        )
    }
}

private func buildRealtimeTranscriptionSession(
    modelId: String,
    inputAudioFormat: TranscriptionModelV4StreamOptions.InputAudioFormat,
    providerOptions: OpenAITranscriptionProviderOptions?
) -> JSONValue {
    var format: JSONObject = [
        "type": .string(inputAudioFormat.type)
    ]
    if let rate = inputAudioFormat.rate {
        format["rate"] = .number(Double(rate))
    }

    var transcription: JSONObject = [
        "model": .string(modelId)
    ]
    if let language = providerOptions?.language {
        transcription["language"] = .string(language)
    }
    if let delay = providerOptions?.streaming?.delay {
        transcription["delay"] = .string(delay)
    }

    var session: JSONObject = [
        "type": .string("transcription"),
        "audio": .object([
            "input": .object([
                "format": .object(format),
                "transcription": .object(transcription),
                "turn_detection": .null
            ])
        ])
    ]
    if let include = providerOptions?.streaming?.include {
        session["include"] = .array(include.map(JSONValue.string))
    }

    return .object([
        "type": .string("session.update"),
        "session": .object(session)
    ])
}

private func createRealtimeTranscriptionStream(
    webSocketFactory: OpenAIWebSocketFactory,
    request: OpenAIWebSocketRequest,
    sessionUpdate: JSONValue,
    language: String?,
    warnings: [SharedV4Warning],
    audio: AsyncThrowingStream<TranscriptionModelV4StreamAudio, Error>,
    abortSignal: (@Sendable () -> Bool)?,
    includeRawChunks: Bool
) -> AsyncThrowingStream<TranscriptionModelV4StreamPart, Error> {
    AsyncThrowingStream(bufferingPolicy: .unbounded) { continuation in
        let connection: any OpenAIWebSocketConnection
        do {
            connection = try webSocketFactory(request)
        } catch {
            continuation.finish(throwing: error)
            return
        }

        let state = RealtimeTranscriptionStreamState()

        let close: @Sendable (Int?) -> Void = { code in
            connection.close(code: code)
        }

        let sendTask = Task {
            do {
                try await connection.waitUntilOpen()
                guard await state.isOpen else { return }

                continuation.yield(.streamStart(warnings: warnings))
                try await connection.send(try jsonString(from: sessionUpdate))

                for try await chunk in audio {
                    try Task.checkCancellation()
                    guard await state.isOpen else {
                        break
                    }
                    if abortSignal?() == true {
                        throw CancellationError()
                    }
                    try await connection.send(
                        try jsonString(from: .object([
                            "type": .string("input_audio_buffer.append"),
                            "audio": .string(base64String(from: chunk))
                        ]))
                    )
                }

                if abortSignal?() == true {
                    throw CancellationError()
                }
                if await state.isOpen {
                    try await connection.send(try jsonString(from: .object([
                        "type": .string("input_audio_buffer.commit")
                    ])))
                }
            } catch {
                if await state.finish() {
                    close(nil)
                    continuation.finish(throwing: error)
                }
            }
        }

        let receiveTask = Task {
            do {
                for try await text in connection.messages {
                    try Task.checkCancellation()

                    let parsed = await safeParseJSON(ParseJSONOptions(text: text))
                    guard case .success(let rawValue, _) = parsed else {
                        continue
                    }

                    if includeRawChunks {
                        continuation.yield(.raw(rawValue: rawValue))
                    }

                    guard case .object(let event) = rawValue,
                          let eventType = stringValue(event["type"])
                    else {
                        continue
                    }

                    switch eventType {
                    case "conversation.item.input_audio_transcription.delta":
                        continuation.yield(.transcriptDelta(
                            id: stringValue(event["item_id"]),
                            delta: stringValue(event["delta"]) ?? "",
                            providerMetadata: nil
                        ))

                    case "conversation.item.input_audio_transcription.completed":
                        if await state.finish() {
                            sendTask.cancel()
                            let id = stringValue(event["item_id"])
                            let text = stringValue(event["transcript"]) ?? ""
                            if let id {
                                continuation.yield(.transcriptFinal(
                                    id: id,
                                    text: text,
                                    startSecond: nil,
                                    endSecond: nil,
                                    channelIndex: nil,
                                    providerMetadata: nil
                                ))
                            }
                            continuation.yield(.finish(
                                text: text,
                                segments: [],
                                language: language,
                                durationInSeconds: nil,
                                providerMetadata: nil
                            ))
                            continuation.finish()
                            close(1000)
                        }
                        return

                    case "error":
                        if await state.finish() {
                            sendTask.cancel()
                            close(nil)
                            continuation.finish(
                                throwing: OpenAIRealtimeTranscriptionError(
                                    message: errorMessage(from: event) ?? "OpenAI realtime error"
                                )
                            )
                        }
                        return

                    default:
                        break
                    }
                }

                if await state.finish() {
                    sendTask.cancel()
                    continuation.finish()
                    close(nil)
                }
            } catch {
                if await state.finish() {
                    sendTask.cancel()
                    close(nil)
                    continuation.finish(throwing: error)
                }
            }
        }

        continuation.onTermination = { @Sendable _ in
            Task {
                _ = await state.finish()
                sendTask.cancel()
                receiveTask.cancel()
                close(nil)
            }
        }
    }
}

private actor RealtimeTranscriptionStreamState {
    private var finished = false

    var isOpen: Bool {
        !finished
    }

    func finish() -> Bool {
        if finished {
            return false
        }
        finished = true
        return true
    }
}

private struct OpenAIRealtimeTranscriptionError: Error, LocalizedError, CustomStringConvertible, Sendable {
    let message: String

    var errorDescription: String? { message }
    var description: String { message }
}

private func makeWebSocketURL(from url: String) throws -> URL {
    guard var components = URLComponents(string: url) else {
        throw InvalidArgumentError(argument: "url", message: "invalid OpenAI realtime URL")
    }

    switch components.scheme?.lowercased() {
    case "https":
        components.scheme = "wss"
    case "http":
        components.scheme = "ws"
    case "wss", "ws":
        break
    default:
        throw InvalidArgumentError(argument: "url", message: "invalid OpenAI realtime URL scheme")
    }

    guard let webSocketURL = components.url else {
        throw InvalidArgumentError(argument: "url", message: "invalid OpenAI realtime URL")
    }
    return webSocketURL
}

private func openAIRealtimeProtocols(headers: [String: String]) -> [String] {
    let authorization = headers["Authorization"] ?? headers["authorization"]
    guard let authorization, authorization.hasPrefix("Bearer ") else {
        return ["realtime"]
    }

    let token = String(authorization.dropFirst("Bearer ".count))
    return ["realtime", "openai-insecure-api-key.\(token)"]
}

private func jsonString(from value: JSONValue) throws -> String {
    let foundation = jsonValueToFoundation(value)
    guard JSONSerialization.isValidJSONObject(foundation) else {
        throw InvalidArgumentError(argument: "body", message: "invalid OpenAI realtime JSON body")
    }
    let data = try JSONSerialization.data(withJSONObject: foundation, options: [.sortedKeys])
    guard let text = String(data: data, encoding: .utf8) else {
        throw InvalidArgumentError(argument: "body", message: "invalid OpenAI realtime JSON body")
    }
    return text
}

private func base64String(from audio: TranscriptionModelV4StreamAudio) -> String {
    switch audio {
    case .binary(let data):
        return data.base64EncodedString()
    case .base64(let base64):
        return base64
    }
}

private func stringValue(_ value: JSONValue?) -> String? {
    guard case .string(let string) = value else {
        return nil
    }
    return string
}

private func errorMessage(from event: JSONObject) -> String? {
    guard case .object(let errorObject) = event["error"] else {
        return nil
    }
    return stringValue(errorObject["message"])
}
