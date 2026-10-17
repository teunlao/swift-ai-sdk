import Foundation
import AISDKProvider
import AISDKProviderUtils

public final class OpenAISpeechModel: SpeechModelV4 {
    public let modelId: String
    private let config: OpenAIConfig

    public init(modelId: OpenAISpeechModelId, config: OpenAIConfig) {
        self.modelId = modelId.rawValue
        self.config = config
    }

    public var provider: String { config.provider }

    public func doGenerate(options: SpeechModelV4CallOptions) async throws -> SpeechModelV4Result {
        let timestamp = config._internal?.currentDate?() ?? Date()
        let settings = try await parseProviderOptions(provider: "openai", providerOptions: options.providerOptions,
            schema: openAISpeechModelOptionsSchema)
        var warnings: [SharedV4Warning] = []
        var body: JSONObject = [
            "model": .string(modelId), "input": .string(options.text),
            "voice": .string(options.voice ?? "alloy"), "response_format": .string("mp3")
        ]
        if let speed = options.speed { body["speed"] = .number(speed) }
        if let instructions = options.instructions { body["instructions"] = .string(instructions) }
        if let format = options.outputFormat, !format.isEmpty {
            if let format = OpenAISpeechAPITypes.ResponseFormat(rawValue: format) {
                body["response_format"] = .string(format.rawValue)
            } else {
                warnings.append(.unsupported(feature: "outputFormat",
                    details: "Unsupported output format: \(format). Using mp3 instead."))
            }
        }
        if let speed = settings?.speed { body["speed"] = .number(speed) }
        if let instructions = settings?.instructions { body["instructions"] = .string(instructions) }
        if let language = options.language, !language.isEmpty {
            warnings.append(.unsupported(feature: "language",
                details: "OpenAI speech models do not support language selection. Language parameter \"\(language)\" was ignored."))
        }

        let url = try config.url(.init(modelId: modelId, path: "/audio/speech"))
        let headers = combineHeaders(try config.headers(), options.headers?.mapValues(Optional.some)).compactMapValues { $0 }
        let response = try await postJsonToAPI(url: url, headers: headers, body: JSONValue.object(body),
            failedResponseHandler: openAIFailedResponseHandler,
            successfulResponseHandler: createBinaryResponseHandler(),
            isAborted: options.abortSignal, fetch: config.fetch)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let requestBody = String(decoding: try encoder.encode(JSONValue.object(body)), as: UTF8.self)
        return SpeechModelV4Result(
            audio: .binary(response.value), warnings: warnings, request: .init(body: requestBody),
            response: .init(timestamp: timestamp, modelId: modelId, headers: response.responseHeaders, body: response.rawValue)
        )
    }
}
