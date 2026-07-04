import Foundation
import AISDKProvider
import AISDKProviderUtils

private struct OpenAISpeechModelCore: Sendable {
    private let modelIdentifier: OpenAISpeechModelId
    private let config: OpenAIConfig

    init(modelId: OpenAISpeechModelId, config: OpenAIConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    var provider: String { config.provider }
    var modelId: String { modelIdentifier.rawValue }

    func doGenerate(
        text: String,
        voice: String?,
        outputFormat: String?,
        instructions: String?,
        speed: Double?,
        language: String?,
        providerOptions: SharedV4ProviderOptions?,
        abortSignal: (@Sendable () -> Bool)?,
        headers: SharedV4Headers?
    ) async throws -> OpenAISpeechCoreResult {
        let prepared = try await prepareRequest(
            text: text,
            voice: voice,
            outputFormat: outputFormat,
            instructions: instructions,
            speed: speed,
            language: language,
            providerOptions: providerOptions
        )
        let currentDate = config._internal?.currentDate?() ?? Date()

        let headers = combineHeaders(try config.headers(), headers?.mapValues { Optional($0) })
            .compactMapValues { $0 }

        let response = try await postJsonToAPI(
            url: config.url(.init(modelId: modelIdentifier.rawValue, path: "/audio/speech")),
            headers: headers,
            body: JSONValue.object(prepared.body),
            failedResponseHandler: openAIFailedResponseHandler,
            successfulResponseHandler: createBinaryResponseHandler(),
            isAborted: abortSignal,
            fetch: config.fetch
        )

        let requestBodyString = jsonString(from: prepared.body)

        return OpenAISpeechCoreResult(
            audio: response.value,
            warnings: prepared.warnings,
            requestBody: requestBodyString,
            timestamp: currentDate,
            modelId: modelIdentifier.rawValue,
            responseHeaders: response.responseHeaders,
            responseBody: response.rawValue
        )
    }

    private struct PreparedRequest {
        let body: [String: JSONValue]
        let warnings: [SharedV4Warning]
    }

    private func prepareRequest(
        text: String,
        voice: String?,
        outputFormat: String?,
        instructions: String?,
        speed: Double?,
        language: String?,
        providerOptions: SharedV4ProviderOptions?
    ) async throws -> PreparedRequest {
        var warnings: [SharedV4Warning] = []

        // Parity with upstream TS: provider options are parsed for validation but not applied to request body.
        _ = try await parseProviderOptions(
            provider: "openai",
            providerOptions: providerOptions,
            schema: openAISpeechProviderOptionsSchema
        )

        let voice = voice ?? "alloy"
        var body: [String: JSONValue] = [
            "model": .string(modelIdentifier.rawValue),
            "input": .string(text),
            "voice": .string(voice),
            "response_format": .string("mp3")
        ]

        if let speed {
            body["speed"] = .number(speed)
        }
        if let instructions {
            body["instructions"] = .string(instructions)
        }
        if let format = outputFormat {
            if allowedOutputFormats.contains(format) {
                body["response_format"] = .string(format)
            } else {
                warnings.append(.unsupported(
                    feature: "outputFormat",
                    details: "Unsupported output format: \(format). Using mp3 instead."
                ))
            }
        }

        if let language {
            warnings.append(.unsupported(
                feature: "language",
                details: "OpenAI speech models do not support language selection. Language parameter \"\(language)\" was ignored."
            ))
        }

        return PreparedRequest(body: body, warnings: warnings)
    }

    private func jsonString(from body: [String: JSONValue]) -> String? {
        do {
            let data = try JSONEncoder().encode(JSONValue.object(body))
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    private let allowedOutputFormats: Set<String> = ["mp3", "opus", "aac", "flac", "wav", "pcm"]
}

private struct OpenAISpeechCoreResult: @unchecked Sendable {
    let audio: Data
    let warnings: [SharedV4Warning]
    let requestBody: String?
    let timestamp: Date
    let modelId: String
    let responseHeaders: SharedV2Headers?
    let responseBody: Any?
}

public final class OpenAISpeechModel: SpeechModelV3 {
    private let core: OpenAISpeechModelCore

    public init(modelId: OpenAISpeechModelId, config: OpenAIConfig) {
        self.core = OpenAISpeechModelCore(modelId: modelId, config: config)
    }

    public var provider: String { core.provider }
    public var modelId: String { core.modelId }

    public func doGenerate(options: SpeechModelV3CallOptions) async throws -> SpeechModelV3Result {
        let result = try await core.doGenerate(
            text: options.text,
            voice: options.voice,
            outputFormat: options.outputFormat,
            instructions: options.instructions,
            speed: options.speed,
            language: options.language,
            providerOptions: options.providerOptions,
            abortSignal: options.abortSignal,
            headers: options.headers
        )

        return SpeechModelV3Result(
            audio: .binary(result.audio),
            warnings: result.warnings.map(convertSharedV4WarningToV3),
            request: SpeechModelV3Result.RequestInfo(body: result.requestBody),
            response: SpeechModelV3Result.ResponseInfo(
                timestamp: result.timestamp,
                modelId: result.modelId,
                headers: result.responseHeaders,
                body: result.responseBody
            ),
            providerMetadata: nil
        )
    }

    func asV4() -> OpenAISpeechModelV4 {
        OpenAISpeechModelV4(core: core)
    }
}

public final class OpenAISpeechModelV4: SpeechModelV4 {
    private let core: OpenAISpeechModelCore

    public init(modelId: OpenAISpeechModelId, config: OpenAIConfig) {
        self.core = OpenAISpeechModelCore(modelId: modelId, config: config)
    }

    fileprivate init(core: OpenAISpeechModelCore) {
        self.core = core
    }

    public var provider: String { core.provider }
    public var modelId: String { core.modelId }

    public func doGenerate(options: SpeechModelV4CallOptions) async throws -> SpeechModelV4Result {
        let result = try await core.doGenerate(
            text: options.text,
            voice: options.voice,
            outputFormat: options.outputFormat,
            instructions: options.instructions,
            speed: options.speed,
            language: options.language,
            providerOptions: options.providerOptions,
            abortSignal: options.abortSignal,
            headers: options.headers
        )

        return SpeechModelV4Result(
            audio: .binary(result.audio),
            warnings: result.warnings,
            request: SpeechModelV4Result.RequestInfo(body: result.requestBody),
            response: SpeechModelV4Result.ResponseInfo(
                timestamp: result.timestamp,
                modelId: result.modelId,
                headers: result.responseHeaders,
                body: result.responseBody
            ),
            providerMetadata: nil
        )
    }
}

private func convertSharedV4WarningToV3(_ value: SharedV4Warning) -> SharedV3Warning {
    switch value {
    case let .unsupported(feature, details):
        return .unsupported(feature: feature, details: details)
    case let .compatibility(feature, details):
        return .compatibility(feature: feature, details: details)
    case let .deprecated(setting, message):
        return .other(message: "\(setting): \(message)")
    case let .other(message):
        return .other(message: message)
    }
}
