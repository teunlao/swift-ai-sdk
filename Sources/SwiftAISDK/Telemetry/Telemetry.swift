import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 A lifecycle event as delivered to a telemetry integration: the event and the
 recording settings of the call.

 Port of `InferTelemetryEvent` from `@ai-sdk/ai/src/telemetry/telemetry.ts`.
 Event fields are reachable as members (`event.callId`).
 */
@dynamicMemberLookup
public struct TelemetryEvent<Event: Sendable>: Sendable {
    /// The lifecycle event.
    public let event: Event

    /// Whether inputs may be recorded (`nil` means yes).
    public let recordInputs: Bool?

    /// Whether outputs may be recorded (`nil` means yes).
    public let recordOutputs: Bool?

    /// Identifier of the function, for grouping telemetry data.
    public let functionId: String?

    public init(event: Event, recordInputs: Bool? = nil, recordOutputs: Bool? = nil, functionId: String? = nil) {
        self.event = event
        self.recordInputs = recordInputs
        self.recordOutputs = recordOutputs
        self.functionId = functionId
    }

    public subscript<T>(dynamicMember keyPath: KeyPath<Event, T>) -> T {
        event[keyPath: keyPath]
    }
}

/**
 Event passed to `onStart`: the start of a generation operation.

 Port of the upstream `OperationStartEvent` union; distinguish operations by
 case or by `operationId`.
 */
public enum TelemetryStartEvent: Sendable {
    case generateText(GenerateTextStartEvent)
    case generateObject(GenerateObjectStartEvent)
    case embed(EmbedStartEvent<String>)
    case embedMany(EmbedStartEvent<[String]>)
    /// Rerank documents are carried as JSON: a string or an object per document.
    case rerank(RerankStartEvent<JSONValue>)
    case generateSpeech(GenerateSpeechStartEvent)
    case transcribe(TranscriptionStartEvent)

    public var callId: String {
        switch self {
        case .generateText(let event): return event.callId
        case .generateObject(let event): return event.callId
        case .embed(let event): return event.callId
        case .embedMany(let event): return event.callId
        case .rerank(let event): return event.callId
        case .generateSpeech(let event): return event.callId
        case .transcribe(let event): return event.callId
        }
    }

    public var operationId: String {
        switch self {
        case .generateText(let event): return event.operationId
        case .generateObject(let event): return event.operationId
        case .embed(let event): return event.operationId
        case .embedMany(let event): return event.operationId
        case .rerank(let event): return event.operationId
        case .generateSpeech(let event): return event.operationId
        case .transcribe(let event): return event.operationId
        }
    }
}

/**
 Event passed to `onEnd`: the end of a generation operation.

 Port of the upstream `OperationEndEvent` union.
 */
public enum TelemetryEndEvent: Sendable {
    case generateText(GenerateTextEndEvent)
    case generateObject(GenerateObjectEndEvent<JSONValue>)
    case embed(EmbedEndEvent<String, Embedding>)
    case embedMany(EmbedEndEvent<[String], [Embedding]>)
    /// Rerank documents are carried as JSON: a string or an object per document.
    case rerank(RerankEndEvent<JSONValue>)
    case generateSpeech(GenerateSpeechEndEvent)
    case transcribe(TranscriptionEndEvent)

    public var callId: String {
        switch self {
        case .generateText(let event): return event.callId
        case .generateObject(let event): return event.callId
        case .embed(let event): return event.callId
        case .embedMany(let event): return event.callId
        case .rerank(let event): return event.callId
        case .generateSpeech(let event): return event.callId
        case .transcribe(let event): return event.callId
        }
    }
}

/// Event passed to `onError` when an operation fails.
public struct TelemetryErrorEvent: Sendable {
    public let callId: String
    public let error: any Error

    public init(callId: String, error: any Error) {
        self.callId = callId
        self.error = error
    }
}

/**
 A telemetry integration: receives lifecycle events of AI SDK operations.

 Port of the `Telemetry` interface from `@ai-sdk/ai/src/telemetry/telemetry.ts`.
 Every method has a no-op default; implement the ones you need. Errors thrown
 by an integration never interrupt the operation.
 */
public protocol Telemetry: Sendable {
    /// An operation begins: text, object, embedding, reranking, speech or non-streaming transcription.
    func onStart(_ event: TelemetryEvent<TelemetryStartEvent>) async throws

    /// A step (single model invocation plus tool execution) begins.
    func onStepStart(_ event: TelemetryEvent<GenerateTextStepStartEvent>) async throws

    /// A provider model call is about to begin.
    func onLanguageModelCallStart(_ event: TelemetryEvent<LanguageModelCallStartEvent>) async throws

    /// A provider model call finished and its response was parsed, before tool execution.
    func onLanguageModelCallEnd(_ event: TelemetryEvent<LanguageModelCallEndEvent>) async throws

    /// A tool execution begins.
    func onToolExecutionStart(_ event: TelemetryEvent<ToolExecutionStartEvent>) async throws

    /// A tool execution finished, successfully or with an error.
    func onToolExecutionEnd(_ event: TelemetryEvent<ToolExecutionEndEvent>) async throws

    /// A step finished.
    func onStepEnd(_ event: TelemetryEvent<any StepResult>) async throws

    /// The object generation step begins.
    func onObjectStepStart(_ event: TelemetryEvent<GenerateObjectStepStartEvent>) async throws

    /// The object generation step finished, before parsing and validation.
    func onObjectStepEnd(_ event: TelemetryEvent<GenerateObjectStepEndEvent>) async throws

    /// An embedding model call (`doEmbed`) begins; `embedMany` makes one per chunk.
    func onEmbedStart(_ event: TelemetryEvent<EmbeddingModelCallStartEvent>) async throws

    /// An embedding model call finished.
    func onEmbedEnd(_ event: TelemetryEvent<EmbeddingModelCallEndEvent>) async throws

    /// A reranking model call (`doRerank`) begins.
    func onRerankStart(_ event: TelemetryEvent<RerankingModelCallStartEvent>) async throws

    /// A reranking model call finished.
    func onRerankEnd(_ event: TelemetryEvent<RerankingModelCallEndEvent>) async throws

    /// A streaming transcription begins.
    func onStreamTranscriptionStart(_ event: TelemetryEvent<StreamTranscriptionStartEvent>) async throws

    /// A streaming transcription finished.
    func onStreamTranscriptionEnd(_ event: TelemetryEvent<StreamTranscriptionEndEvent>) async throws

    /// An operation finished.
    func onEnd(_ event: TelemetryEvent<TelemetryEndEvent>) async throws

    /// A streaming generation was aborted.
    func onAbort(_ event: TelemetryEvent<GenerateTextAbortEvent>) async throws

    /// An operation failed with an unrecoverable error.
    func onError(_ event: TelemetryEvent<TelemetryErrorEvent>) async throws

    /**
     Runs the provider call in an integration-specific context, so instrumented
     provider requests become children of the model call.
     */
    func executeLanguageModelCall<T: Sendable>(
        _ event: TelemetryEvent<LanguageModelCallStartEvent>,
        execute: @Sendable () async throws -> T
    ) async throws -> T

    /**
     Runs a tool's execute function in an integration-specific context, so
     nested AI SDK calls inside the tool become children of the tool execution.
     */
    func executeTool<T: Sendable>(
        _ event: TelemetryEvent<ToolExecutionStartEvent>,
        execute: @Sendable () async throws -> T
    ) async throws -> T
}

public extension Telemetry {
    func onStart(_ event: TelemetryEvent<TelemetryStartEvent>) async throws {}
    func onStepStart(_ event: TelemetryEvent<GenerateTextStepStartEvent>) async throws {}
    func onLanguageModelCallStart(_ event: TelemetryEvent<LanguageModelCallStartEvent>) async throws {}
    func onLanguageModelCallEnd(_ event: TelemetryEvent<LanguageModelCallEndEvent>) async throws {}
    func onToolExecutionStart(_ event: TelemetryEvent<ToolExecutionStartEvent>) async throws {}
    func onToolExecutionEnd(_ event: TelemetryEvent<ToolExecutionEndEvent>) async throws {}
    func onStepEnd(_ event: TelemetryEvent<any StepResult>) async throws {}
    func onObjectStepStart(_ event: TelemetryEvent<GenerateObjectStepStartEvent>) async throws {}
    func onObjectStepEnd(_ event: TelemetryEvent<GenerateObjectStepEndEvent>) async throws {}
    func onEmbedStart(_ event: TelemetryEvent<EmbeddingModelCallStartEvent>) async throws {}
    func onEmbedEnd(_ event: TelemetryEvent<EmbeddingModelCallEndEvent>) async throws {}
    func onRerankStart(_ event: TelemetryEvent<RerankingModelCallStartEvent>) async throws {}
    func onRerankEnd(_ event: TelemetryEvent<RerankingModelCallEndEvent>) async throws {}
    func onStreamTranscriptionStart(_ event: TelemetryEvent<StreamTranscriptionStartEvent>) async throws {}
    func onStreamTranscriptionEnd(_ event: TelemetryEvent<StreamTranscriptionEndEvent>) async throws {}
    func onEnd(_ event: TelemetryEvent<TelemetryEndEvent>) async throws {}
    func onAbort(_ event: TelemetryEvent<GenerateTextAbortEvent>) async throws {}
    func onError(_ event: TelemetryEvent<TelemetryErrorEvent>) async throws {}

    func executeLanguageModelCall<T: Sendable>(
        _ event: TelemetryEvent<LanguageModelCallStartEvent>,
        execute: @Sendable () async throws -> T
    ) async throws -> T {
        try await execute()
    }

    func executeTool<T: Sendable>(
        _ event: TelemetryEvent<ToolExecutionStartEvent>,
        execute: @Sendable () async throws -> T
    ) async throws -> T {
        try await execute()
    }
}
