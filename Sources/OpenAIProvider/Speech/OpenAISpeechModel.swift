import Foundation
import AISDKProvider
import AISDKProviderUtils

public final class OpenAISpeechModel: SpeechModelV3 {
    private let modelIdentifier: OpenAISpeechModelId
    private let config: OpenAIConfig

    public init(modelId: OpenAISpeechModelId, config: OpenAIConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }

    public func doGenerate(options: SpeechModelV3CallOptions) async throws -> SpeechModelV3Result {
        let prepared = try await prepareRequest(options: options)
        let currentDate = config._internal?.currentDate?() ?? Date()

        let headers = combineHeaders(try config.headers(), options.headers?.mapValues { Optional($0) })
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
        let warnings: [SharedV3Warning]
    }

    private func prepareRequest(options: SpeechModelV3CallOptions) async throws -> PreparedRequest {
        var warnings: [SharedV3Warning] = []

        // Parity with upstream TS: provider options are parsed for validation but not applied to request body.
        _ = try await parseProviderOptions(
            provider: "openai",
            providerOptions: options.providerOptions,
            schema: openAISpeechProviderOptionsSchema
        )

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
        if let format = options.outputFormat {
            if allowedOutputFormats.contains(format) {
                body["response_format"] = .string(format)
            } else {
                warnings.append(.unsupported(
                    feature: "outputFormat",
                    details: "Unsupported output format: \(format). Using mp3 instead."
                ))
            }
        }

        if let language = options.language {
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
