import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Event passed to `onStart` when a `generateObject` / `streamObject` operation begins.

 Port of `GenerateObjectStartEvent` from `@ai-sdk/ai/src/generate-object/structured-output-events.ts`.
 */
public struct GenerateObjectStartEvent: Sendable {
    public let callId: String
    public let operationId: String
    public let provider: String
    public let modelId: String
    public let system: Instructions?
    public let prompt: PromptContent?
    public let messages: [ModelMessage]?
    public let maxOutputTokens: Int?
    public let temperature: Double?
    public let topP: Double?
    public let topK: Int?
    public let presencePenalty: Double?
    public let frequencyPenalty: Double?
    public let seed: Int?
    public let maxRetries: Int
    public let headers: [String: String]?
    public let providerOptions: ProviderOptions?
    /// Output kind: `object`, `array`, `enum` or `no-schema`.
    public let output: String
    public let schema: JSONValue?
    public let schemaName: String?
    public let schemaDescription: String?

    public init(
        callId: String,
        operationId: String,
        provider: String,
        modelId: String,
        system: Instructions?,
        prompt: PromptContent?,
        messages: [ModelMessage]?,
        maxOutputTokens: Int?,
        temperature: Double?,
        topP: Double?,
        topK: Int?,
        presencePenalty: Double?,
        frequencyPenalty: Double?,
        seed: Int?,
        maxRetries: Int,
        headers: [String: String]?,
        providerOptions: ProviderOptions?,
        output: String,
        schema: JSONValue?,
        schemaName: String?,
        schemaDescription: String?
    ) {
        self.callId = callId
        self.operationId = operationId
        self.provider = provider
        self.modelId = modelId
        self.system = system
        self.prompt = prompt
        self.messages = messages
        self.maxOutputTokens = maxOutputTokens
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.presencePenalty = presencePenalty
        self.frequencyPenalty = frequencyPenalty
        self.seed = seed
        self.maxRetries = maxRetries
        self.headers = headers
        self.providerOptions = providerOptions
        self.output = output
        self.schema = schema
        self.schemaName = schemaName
        self.schemaDescription = schemaDescription
    }
}

/**
 Event passed to `onObjectStepStart` before the single object generation step.

 Port of `GenerateObjectStepStartEvent` from `@ai-sdk/ai/src/generate-object/structured-output-events.ts`.
 */
public struct GenerateObjectStepStartEvent: Sendable {
    public let callId: String
    public let stepNumber: Int
    public let provider: String
    public let modelId: String
    public let providerOptions: ProviderOptions?
    public let headers: [String: String]?
    public let promptMessages: LanguageModelV4Prompt?

    public init(
        callId: String,
        provider: String,
        modelId: String,
        providerOptions: ProviderOptions?,
        headers: [String: String]?,
        promptMessages: LanguageModelV4Prompt?
    ) {
        self.callId = callId
        self.stepNumber = 0
        self.provider = provider
        self.modelId = modelId
        self.providerOptions = providerOptions
        self.headers = headers
        self.promptMessages = promptMessages
    }
}

/**
 Event passed to `onObjectStepEnd` with the raw result before parsing and validation.

 Port of `GenerateObjectStepEndEvent` from `@ai-sdk/ai/src/generate-object/structured-output-events.ts`.
 */
public struct GenerateObjectStepEndEvent: Sendable {
    public let callId: String
    public let stepNumber: Int
    public let provider: String
    public let modelId: String
    public let finishReason: FinishReason
    public let usage: LanguageModelUsage
    public let objectText: String
    public let reasoning: String?
    public let warnings: [CallWarning]?
    public let request: LanguageModelRequestMetadata
    public let response: LanguageModelResponseMetadata
    public let responseBody: JSONValue?
    public let providerMetadata: ProviderMetadata?
    public let msToFirstChunk: Double?

    public init(
        callId: String,
        provider: String,
        modelId: String,
        finishReason: FinishReason,
        usage: LanguageModelUsage,
        objectText: String,
        reasoning: String?,
        warnings: [CallWarning]?,
        request: LanguageModelRequestMetadata,
        response: LanguageModelResponseMetadata,
        responseBody: JSONValue? = nil,
        providerMetadata: ProviderMetadata?,
        msToFirstChunk: Double?
    ) {
        self.callId = callId
        self.stepNumber = 0
        self.provider = provider
        self.modelId = modelId
        self.finishReason = finishReason
        self.usage = usage
        self.objectText = objectText
        self.reasoning = reasoning
        self.warnings = warnings
        self.request = request
        self.response = response
        self.responseBody = responseBody
        self.providerMetadata = providerMetadata
        self.msToFirstChunk = msToFirstChunk
    }
}

/**
 Event passed to `onEnd` when an object generation finishes, successfully or not.

 Port of `GenerateObjectEndEvent` from `@ai-sdk/ai/src/generate-object/structured-output-events.ts`.
 The object is carried as JSON.
 */
public struct GenerateObjectEndEvent: Sendable {
    public let callId: String
    public let object: JSONValue?
    public let error: (any Error)?
    public let reasoning: String?
    public let finishReason: FinishReason
    public let usage: LanguageModelUsage
    public let warnings: [CallWarning]?
    public let request: LanguageModelRequestMetadata
    public let response: LanguageModelResponseMetadata
    public let providerMetadata: ProviderMetadata?

    public init(
        callId: String,
        object: JSONValue?,
        error: (any Error)?,
        reasoning: String?,
        finishReason: FinishReason,
        usage: LanguageModelUsage,
        warnings: [CallWarning]?,
        request: LanguageModelRequestMetadata,
        response: LanguageModelResponseMetadata,
        providerMetadata: ProviderMetadata?
    ) {
        self.callId = callId
        self.object = object
        self.error = error
        self.reasoning = reasoning
        self.finishReason = finishReason
        self.usage = usage
        self.warnings = warnings
        self.request = request
        self.response = response
        self.providerMetadata = providerMetadata
    }
}
