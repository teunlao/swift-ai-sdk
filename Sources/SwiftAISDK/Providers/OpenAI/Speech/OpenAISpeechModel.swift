import Foundation
import AISDKProvider
import AISDKProviderUtils

public final class OpenAISpeechModel: SpeechModelV3 {
    private let modelIdentifier: OpenAISpeechModelId
    private let config: OpenAIConfig
    private let providerOptionsName: String

    public init(modelId: OpenAISpeechModelId, config: OpenAIConfig) {
        self.modelIdentifier = modelId
        self.config = config
        if let prefix = config.provider.split(separator: ".").first {
            self.providerOptionsName = String(prefix)
        } else {
            self.providerOptionsName = "openai"
        }
    }

    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }

    public func doGenerate(options: SpeechModelV3CallOptions) async throws -> SpeechModelV3Result {
        let prepared = try await prepareRequest(options: options)
        let currentDate = config._internal?.currentDate?() ?? Date()

        let headers = combineHeaders(config.headers(), options.headers?.mapValues { Optional($0) })
            .compactMapValues { $0 }

        let response = try await postJsonToAPI(
            url: config.url(.init(modelId: modelIdentifier.rawValue, path: "/audio/speech")),
            headers: headers,
            body: JSONValue.object(prepared.body),
            failedResponseHandler: openAIFailedResponseHandler,
            successfulResponseHandler: createBinaryResponseHandler(),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let requestBodyString = jsonString(from: prepared.body)

        return SpeechModelV3Result(
            audio: .binary(response.value),
            warnings: prepared.warnings,
            request: SpeechModelV3Result.RequestInfo(body: requestBodyString),
            response: SpeechModelV3Result.ResponseInfo(
                timestamp: currentDate,
                modelId: modelIdentifier.rawValue,
                headers: response.responseHeaders,
                body: response.rawValue
            ),
            providerMetadata: nil
        )
    }

    private struct PreparedRequest {
        let body: [String: JSONValue]
        let warnings: [SpeechModelV3CallWarning]
    }

    private func prepareRequest(options: SpeechModelV3CallOptions) async throws -> PreparedRequest {
        var warnings: [SpeechModelV3CallWarning] = []

        let _: OpenAISpeechProviderOptions? = try await parseProviderOptions(
            provider: "openai",
            providerOptions: options.providerOptions,
            schema: openAISpeechProviderOptionsSchema
        )

        if providerOptionsName != "openai" {
            _ = try await parseProviderOptions(
                provider: providerOptionsName,
                providerOptions: options.providerOptions,
                schema: openAISpeechProviderOptionsSchema
            )
        }

        let voice = options.voice ?? "alloy"
        var body: [String: JSONValue] = [
            "model": .string(modelIdentifier.rawValue),
            "input": .string(options.text),
            "voice": .string(voice),
            "response_format": .string("mp3")
        ]

        if let speed = options.speed {
            body["speed"] = .number(speed)
        }
        if let instructions = options.instructions {
            body["instructions"] = .string(instructions)
        }

        if let outputFormat = options.outputFormat {
            if allowedOutputFormats.contains(outputFormat) {
                body["response_format"] = .string(outputFormat)
            } else {
                warnings.append(.unsupportedSetting(
                    setting: "outputFormat",
                    details: "Unsupported output format: \(outputFormat). Using mp3 instead."
                ))
            }
        }

        if let language = options.language {
            warnings.append(.unsupportedSetting(
                setting: "language",
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
