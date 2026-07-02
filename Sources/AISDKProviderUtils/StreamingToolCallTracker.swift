import Foundation
import AISDKProvider

/// Minimal function payload carried by streaming tool-call deltas.
public struct StreamingToolCallFunctionDelta: Sendable, Equatable {
    public let name: String?
    public let arguments: String?

    public init(name: String? = nil, arguments: String? = nil) {
        self.name = name
        self.arguments = arguments
    }
}

/// Minimal streaming tool-call delta used by OpenAI-compatible stream parsers.
public struct StreamingToolCallDelta: Sendable, Equatable {
    public let index: Int?
    public let id: String?
    public let type: String?
    public let function: StreamingToolCallFunctionDelta?
    public let providerMetadata: SharedV4ProviderMetadata?

    public init(
        index: Int? = nil,
        id: String? = nil,
        type: String? = nil,
        function: StreamingToolCallFunctionDelta? = nil,
        providerMetadata: SharedV4ProviderMetadata? = nil
    ) {
        self.index = index
        self.id = id
        self.type = type
        self.function = function
        self.providerMetadata = providerMetadata
    }
}

/// Tool-call type validation policy.
public enum StreamingToolCallTypeValidation: Sendable, Equatable {
    case none
    case ifPresent
    case required
}

/// Options for `StreamingToolCallTracker`.
public struct StreamingToolCallTrackerOptions: Sendable {
    public let generateId: IDGenerator
    public let typeValidation: StreamingToolCallTypeValidation
    public let extractMetadata: (@Sendable (StreamingToolCallDelta) -> SharedV4ProviderMetadata?)?
    public let buildToolCallProviderMetadata: (@Sendable (SharedV4ProviderMetadata?) -> SharedV4ProviderMetadata?)?

    public init(
        generateId: @escaping IDGenerator = generateID,
        typeValidation: StreamingToolCallTypeValidation = .none,
        extractMetadata: (@Sendable (StreamingToolCallDelta) -> SharedV4ProviderMetadata?)? = nil,
        buildToolCallProviderMetadata: (@Sendable (SharedV4ProviderMetadata?) -> SharedV4ProviderMetadata?)? = nil
    ) {
        self.generateId = generateId
        self.typeValidation = typeValidation
        self.extractMetadata = extractMetadata
        self.buildToolCallProviderMetadata = buildToolCallProviderMetadata
    }
}

/// Tracks streaming tool call state across multiple deltas.
public final class StreamingToolCallTracker: @unchecked Sendable {
    public typealias Enqueue = @Sendable (LanguageModelV4StreamPart) -> Void

    private struct TrackedToolCall: Sendable {
        let id: String
        let name: String
        var arguments: String
        var hasFinished: Bool
        let metadata: SharedV4ProviderMetadata?
    }

    private var toolCalls: [TrackedToolCall?] = []
    private let enqueue: Enqueue
    private let generateId: IDGenerator
    private let typeValidation: StreamingToolCallTypeValidation
    private let extractMetadata: (@Sendable (StreamingToolCallDelta) -> SharedV4ProviderMetadata?)?
    private let buildToolCallProviderMetadata: (@Sendable (SharedV4ProviderMetadata?) -> SharedV4ProviderMetadata?)?

    public init(
        enqueue: @escaping Enqueue,
        options: StreamingToolCallTrackerOptions = StreamingToolCallTrackerOptions()
    ) {
        self.enqueue = enqueue
        self.generateId = options.generateId
        self.typeValidation = options.typeValidation
        self.extractMetadata = options.extractMetadata
        self.buildToolCallProviderMetadata = options.buildToolCallProviderMetadata
    }

    /// Processes one streaming tool-call delta and emits any resulting stream parts.
    public func processDelta(_ toolCallDelta: StreamingToolCallDelta) throws {
        let index = toolCallDelta.index ?? toolCalls.count

        if trackedToolCall(at: index) == nil {
            try processNewToolCall(index: index, delta: toolCallDelta)
        } else {
            processExistingToolCall(index: index, delta: toolCallDelta)
        }
    }

    /// Finalizes any unfinished tool calls.
    public func flush() {
        for index in toolCalls.indices {
            guard var toolCall = toolCalls[index], !toolCall.hasFinished else {
                continue
            }

            finishToolCall(&toolCall)
            toolCalls[index] = toolCall
        }
    }

    private func processNewToolCall(index: Int, delta: StreamingToolCallDelta) throws {
        try validateType(delta)

        guard let id = delta.id else {
            throw InvalidResponseDataError(
                data: delta,
                message: "Expected 'id' to be a string."
            )
        }

        guard let name = delta.function?.name else {
            throw InvalidResponseDataError(
                data: delta,
                message: "Expected 'function.name' to be a string."
            )
        }

        enqueue(.toolInputStart(
            id: id,
            toolName: name,
            providerMetadata: nil,
            providerExecuted: nil,
            dynamic: nil,
            title: nil
        ))

        var toolCall = TrackedToolCall(
            id: id,
            name: name,
            arguments: delta.function?.arguments ?? "",
            hasFinished: false,
            metadata: extractMetadata?(delta)
        )

        setTrackedToolCall(toolCall, at: index)

        if !toolCall.arguments.isEmpty {
            enqueue(.toolInputDelta(
                id: toolCall.id,
                delta: toolCall.arguments,
                providerMetadata: nil
            ))
        }

        if isParsableJson(toolCall.arguments) {
            finishToolCall(&toolCall)
            setTrackedToolCall(toolCall, at: index)
        }
    }

    private func processExistingToolCall(index: Int, delta: StreamingToolCallDelta) {
        guard var toolCall = trackedToolCall(at: index), !toolCall.hasFinished else {
            return
        }

        if let arguments = delta.function?.arguments {
            toolCall.arguments += arguments
            enqueue(.toolInputDelta(
                id: toolCall.id,
                delta: arguments,
                providerMetadata: nil
            ))
        }

        if isParsableJson(toolCall.arguments) {
            finishToolCall(&toolCall)
        }

        setTrackedToolCall(toolCall, at: index)
    }

    private func validateType(_ delta: StreamingToolCallDelta) throws {
        switch typeValidation {
        case .none:
            return
        case .ifPresent:
            guard delta.type == nil || delta.type == "function" else {
                throw InvalidResponseDataError(
                    data: delta,
                    message: "Expected 'function' type."
                )
            }
        case .required:
            guard delta.type == "function" else {
                throw InvalidResponseDataError(
                    data: delta,
                    message: "Expected 'function' type."
                )
            }
        }
    }

    private func finishToolCall(_ toolCall: inout TrackedToolCall) {
        enqueue(.toolInputEnd(id: toolCall.id, providerMetadata: nil))

        let providerMetadata = buildToolCallProviderMetadata?(toolCall.metadata)
        enqueue(.toolCall(LanguageModelV4ToolCall(
            toolCallId: toolCall.id,
            toolName: toolCall.name,
            input: toolCall.arguments,
            providerMetadata: providerMetadata
        )))

        toolCall.hasFinished = true
    }

    private func trackedToolCall(at index: Int) -> TrackedToolCall? {
        guard index >= 0, index < toolCalls.count else {
            return nil
        }
        return toolCalls[index]
    }

    private func setTrackedToolCall(_ toolCall: TrackedToolCall, at index: Int) {
        guard index >= 0 else {
            return
        }

        if index >= toolCalls.count {
            toolCalls.append(contentsOf: Array(repeating: nil, count: index - toolCalls.count + 1))
        }

        toolCalls[index] = toolCall
    }
}
