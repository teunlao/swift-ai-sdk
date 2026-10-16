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
    /// Tool call id generator. Blank or repeated outputs are turned into usable unique ids.
    public let generateId: IDGenerator
    public let typeValidation: StreamingToolCallTypeValidation
    public let emitsEmptyInitialArgumentDelta: Bool
    public let extractMetadata: (@Sendable (StreamingToolCallDelta) -> SharedV4ProviderMetadata?)?
    public let buildToolCallProviderMetadata: (@Sendable (SharedV4ProviderMetadata?) -> SharedV4ProviderMetadata?)?

    public init(
        generateId: @escaping IDGenerator = generateID,
        typeValidation: StreamingToolCallTypeValidation = .none,
        emitsEmptyInitialArgumentDelta: Bool = false,
        extractMetadata: (@Sendable (StreamingToolCallDelta) -> SharedV4ProviderMetadata?)? = nil,
        buildToolCallProviderMetadata: (@Sendable (SharedV4ProviderMetadata?) -> SharedV4ProviderMetadata?)? = nil
    ) {
        self.generateId = generateId
        self.typeValidation = typeValidation
        self.emitsEmptyInitialArgumentDelta = emitsEmptyInitialArgumentDelta
        self.extractMetadata = extractMetadata
        self.buildToolCallProviderMetadata = buildToolCallProviderMetadata
    }
}

/**
 Tracks streaming tool call state across the deltas of an OpenAI-compatible chat
 completion stream: correlates deltas to calls, accumulates arguments, emits
 `tool-input-start/delta/end` and `tool-call` parts, and finalizes unfinished
 calls on `flush`.

 Deltas are correlated by wire id, index and name. Providers reuse ids and
 indices across parallel calls or omit them, so neither label alone identifies a
 call; a delta whose call cannot be determined safely is dropped rather than
 attached to the wrong call.

 Port of `@ai-sdk/provider-utils/src/streaming-tool-call-tracker.ts`.
 */
public final class StreamingToolCallTracker: @unchecked Sendable {
    public typealias Enqueue = @Sendable (LanguageModelV4StreamPart) -> Void

    private struct TrackedToolCall {
        let id: String
        let index: Int?
        let name: String
        var arguments: String
        var argumentState: StreamingToolCallArgumentState
        var hasFinished: Bool
        let metadata: SharedV4ProviderMetadata?
    }

    private enum Resolution {
        case existing(Int)
        case new
        case ambiguous
    }

    /// Tracked calls in creation order; a call's position is its sequence number.
    private var toolCalls: [TrackedToolCall] = []
    /// Wire id → sequence numbers, in association order.
    private var toolCallsById: [String: [Int]] = [:]
    /// Wire index → sequence numbers, in association order.
    private var toolCallsByIndex: [Int: [Int]] = [:]
    private var usedToolCallIds: Set<String> = []
    private var nextGeneratedIdSuffixes: [String: Int] = [:]

    private let enqueue: Enqueue
    private let generateId: IDGenerator
    private let typeValidation: StreamingToolCallTypeValidation
    private let emitsEmptyInitialArgumentDelta: Bool
    private let extractMetadata: (@Sendable (StreamingToolCallDelta) -> SharedV4ProviderMetadata?)?
    private let buildToolCallProviderMetadata: (@Sendable (SharedV4ProviderMetadata?) -> SharedV4ProviderMetadata?)?

    public init(
        enqueue: @escaping Enqueue,
        options: StreamingToolCallTrackerOptions = StreamingToolCallTrackerOptions()
    ) {
        self.enqueue = enqueue
        self.generateId = options.generateId
        self.typeValidation = options.typeValidation
        self.emitsEmptyInitialArgumentDelta = options.emitsEmptyInitialArgumentDelta
        self.extractMetadata = options.extractMetadata
        self.buildToolCallProviderMetadata = options.buildToolCallProviderMetadata
    }

    /// Processes one streaming tool-call delta and emits any resulting stream parts.
    public func processDelta(_ toolCallDelta: StreamingToolCallDelta) throws {
        let wireName = toolCallDelta.function?.name
        let hasBlankName = wireName.map { isBlank($0) } ?? false
        let wireId = nonBlank(toolCallDelta.id)
        let name = nonBlank(wireName)
        let argumentsDelta = toolCallDelta.function?.arguments
        let index = toolCallDelta.index

        let resolution = resolveToolCall(
            wireId: wireId,
            index: index,
            name: name,
            hasExplicitCallStart: name != nil && startsWithStructuredValue(argumentsDelta),
            hasEmptyArguments: argumentsDelta.map { isBlank($0) } ?? true
        )

        let sequence: Int
        switch resolution {
        case .ambiguous:
            return

        case .new:
            // Blank names cannot start a usable call, but some providers repeat a
            // blank name on continuations: those were correlated above, so only the
            // unmatched blank-name delta is ignored.
            if hasBlankName {
                return
            }
            sequence = try processNewToolCall(toolCallDelta, wireId: wireId, index: index, name: name)

        case .existing(let existing):
            sequence = existing
            if let wireId {
                associate(sequence, with: wireId)
            }
            processExistingToolCall(sequence, delta: toolCallDelta)
        }

        if let index {
            associate(sequence, with: index)
        }
    }

    /// Finalizes any unfinished tool calls.
    public func flush() {
        // Index order is reliable only when every call has an index. Mixed
        // streams keep insertion order.
        let order: [Int]
        if toolCalls.allSatisfy({ $0.index != nil }) {
            order = toolCalls.indices.sorted { lhs, rhs in
                let lhsIndex = toolCalls[lhs].index ?? 0
                let rhsIndex = toolCalls[rhs].index ?? 0
                return lhsIndex != rhsIndex ? lhsIndex < rhsIndex : lhs < rhs
            }
        } else {
            order = Array(toolCalls.indices)
        }

        for sequence in order where !toolCalls[sequence].hasFinished {
            finishToolCall(sequence)
        }
    }

    /*
     Correlation precedence for streamed deltas:

     | ID evidence | index/name evidence | start evidence         | resolution                               |
     | ----------- | ------------------- | ---------------------- | ---------------------------------------- |
     | known       | matching            | any                    | matching call, new call, or ambiguity    |
     | known       | conflicting         | named                  | new call                                 |
     | unseen      | matching            | structured start       | new call                                 |
     | unseen      | matching            | named empty arguments  | incomplete call, new call, or ambiguity  |
     | unseen      | matching            | continuation           | matching call or ambiguity               |
     | absent      | matching            | any                    | matching call, new call, or ambiguity    |
     | absent      | absent              | named                  | new call                                 |
     | absent      | absent              | unnamed                | sole unfinished call, new call, or ambiguity |
     */
    private func resolveToolCall(
        wireId: String?,
        index: Int?,
        name: String?,
        hasExplicitCallStart: Bool,
        hasEmptyArguments: Bool
    ) -> Resolution {
        let indexedToolCalls = index.flatMap { toolCallsByIndex[$0] }
        let matchingIndexedToolCalls = filterByName(indexedToolCalls, name: name)

        if let wireId {
            if let toolCallsWithId = toolCallsById[wireId] {
                if index != nil {
                    let matching = matchingIndexedToolCalls.filter { toolCallsWithId.contains($0) }
                    let matchingResolution = resolveMatching(matching, hasExplicitCallStart: hasExplicitCallStart)
                    if case .new = matchingResolution {
                        // A named delta with a distinct index starts a new call even when
                        // its wire id and name repeat: providers reuse ids across parallel
                        // calls, so the id/name pair cannot override index evidence.
                        if name != nil {
                            return .new
                        }

                        // Conflicting labels on a continuation cannot be resolved safely.
                        if indexedToolCalls != nil {
                            return .ambiguous
                        }

                        return resolveMatching(toolCallsWithId, hasExplicitCallStart: false)
                    }
                    return matchingResolution
                }

                if let name {
                    let matching = toolCallsWithId.filter { toolCalls[$0].name == name }
                    return resolveMatching(matching, hasExplicitCallStart: hasExplicitCallStart)
                }

                return resolveMatching(toolCallsWithId, hasExplicitCallStart: false)
            }

            if !matchingIndexedToolCalls.isEmpty {
                // A named structured start with an unseen id identifies a new call.
                // Empty arguments also occur when a continuation changes its id: keep
                // the incomplete matching call then, and start a new call only after
                // the matching structured arguments are complete.
                return hasExplicitCallStart
                    ? .new
                    : resolveMatching(
                        matchingIndexedToolCalls,
                        hasExplicitCallStart: name != nil && hasEmptyArguments
                    )
            }

            return .new
        }

        if indexedToolCalls != nil {
            // Repeated names are valid on continuations. A different name at the same
            // index is a new call from a provider that reuses indices across parallel calls.
            return resolveMatching(matchingIndexedToolCalls, hasExplicitCallStart: hasExplicitCallStart)
        }

        if name != nil {
            return .new
        }

        let unfinished = toolCalls.indices.filter { !toolCalls[$0].hasFinished }
        return resolveMatching(unfinished, hasExplicitCallStart: false)
    }

    private func filterByName(_ sequences: [Int]?, name: String?) -> [Int] {
        guard let sequences else {
            return []
        }
        return sequences.filter { name == nil || toolCalls[$0].name == name }
    }

    private func resolveMatching(_ sequences: [Int], hasExplicitCallStart: Bool) -> Resolution {
        if sequences.isEmpty {
            return .new
        }

        // A repeated name can occur on continuations. A fresh structured argument
        // prefix is evidence of another call only after the matching call completed
        // its own structured payload. Without labels, a sole call without a complete
        // structured payload is the only viable continuation target.
        let continuable = sequences.filter { !toolCalls[$0].argumentState.hasCompleteStructuredValue }

        if !hasExplicitCallStart && sequences.count == 1 {
            return .existing(sequences[0])
        }

        if continuable.count == 1 {
            return .existing(continuable[0])
        }

        if continuable.count > 1 || !hasExplicitCallStart {
            return .ambiguous
        }

        return .new
    }

    private func processNewToolCall(
        _ delta: StreamingToolCallDelta,
        wireId: String?,
        index: Int?,
        name: String?
    ) throws -> Int {
        try validateType(delta)

        guard let name else {
            throw InvalidResponseDataError(
                data: delta,
                message: "Expected 'function.name' to be a string."
            )
        }

        let id = try createToolCallId(wireId)

        enqueue(.toolInputStart(
            id: id,
            toolName: name,
            providerMetadata: nil,
            providerExecuted: nil,
            dynamic: nil,
            title: nil
        ))

        let initialArguments = delta.function?.arguments ?? ""
        let sequence = toolCalls.count
        toolCalls.append(TrackedToolCall(
            id: id,
            index: index,
            name: name,
            arguments: initialArguments,
            argumentState: StreamingToolCallArgumentState(initialArguments),
            hasFinished: false,
            metadata: extractMetadata?(delta)
        ))

        if let wireId {
            associate(sequence, with: wireId)
        }

        if !initialArguments.isEmpty || (emitsEmptyInitialArgumentDelta && delta.function?.arguments != nil) {
            enqueue(.toolInputDelta(id: id, delta: initialArguments, providerMetadata: nil))
        }

        // A parsable argument buffer can still be the prefix of a longer argument
        // string, so calls finalize only in flush().
        return sequence
    }

    private func processExistingToolCall(_ sequence: Int, delta: StreamingToolCallDelta) {
        guard !toolCalls[sequence].hasFinished, let arguments = delta.function?.arguments else {
            return
        }

        toolCalls[sequence].argumentState.append(arguments)
        toolCalls[sequence].arguments += arguments
        enqueue(.toolInputDelta(id: toolCalls[sequence].id, delta: arguments, providerMetadata: nil))
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

    private func finishToolCall(_ sequence: Int) {
        let toolCall = toolCalls[sequence]
        enqueue(.toolInputEnd(id: toolCall.id, providerMetadata: nil))

        enqueue(.toolCall(LanguageModelV4ToolCall(
            toolCallId: toolCall.id,
            toolName: toolCall.name,
            input: toolCall.arguments,
            providerMetadata: buildToolCallProviderMetadata?(toolCall.metadata)
        )))

        toolCalls[sequence].hasFinished = true
    }

    private func associate(_ sequence: Int, with wireId: String) {
        if !(toolCallsById[wireId]?.contains(sequence) ?? false) {
            toolCallsById[wireId, default: []].append(sequence)
        }
    }

    private func associate(_ sequence: Int, with index: Int) {
        if !(toolCallsByIndex[index]?.contains(sequence) ?? false) {
            toolCallsByIndex[index, default: []].append(sequence)
        }
    }

    private func createToolCallId(_ wireId: String?) throws -> String {
        if let wireId, !usedToolCallIds.contains(wireId) {
            usedToolCallIds.insert(wireId)
            return wireId
        }

        let generatedId = nonBlank(generateId()) ?? "tool-call"

        if !usedToolCallIds.contains(generatedId) {
            usedToolCallIds.insert(generatedId)
            return generatedId
        }

        // Resume after the last suffix checked for this generated value, so
        // deterministic generators stay bounded.
        let initialSuffix = nextGeneratedIdSuffixes[generatedId] ?? 1
        let maximumSuffix = initialSuffix + usedToolCallIds.count
        for suffix in initialSuffix...maximumSuffix {
            let suffixedId = "\(generatedId)-\(suffix)"
            if !usedToolCallIds.contains(suffixedId) {
                usedToolCallIds.insert(suffixedId)
                nextGeneratedIdSuffixes[generatedId] = suffix + 1
                return suffixedId
            }
        }

        // Unreachable by the pigeonhole principle; guards against an unbounded retry loop.
        throw InvalidResponseDataError(data: nil, message: "Failed to create a unique tool call ID.")
    }

    private func nonBlank(_ value: String?) -> String? {
        guard let value, !isBlank(value) else {
            return nil
        }
        return value
    }

    private func isBlank(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
