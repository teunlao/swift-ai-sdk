import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct Experimental_OpenResponsesNamespacedType: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }
}

public struct Experimental_OpenResponsesExtensionRecord: Sendable, Equatable {
    public let type: String
    public let fields: JSONObject
    public init(type: String, fields: JSONObject = [:]) {
        self.type = type
        var values = fields
        values["type"] = .string(type)
        self.fields = values
    }
}

public struct Experimental_OpenResponsesExtensionItem: Sendable, Equatable {
    public let type: String
    public let id: String
    public let status: String
    public let fields: JSONObject
    public init(type: String, id: String, status: String, fields: JSONObject = [:]) {
        self.type = type
        self.id = id
        self.status = status
        var values = fields
        values["type"] = .string(type)
        values["id"] = .string(id)
        values["status"] = .string(status)
        self.fields = values
    }
    init?(wire: JSONObject) {
        guard case .string(let type) = wire["type"], case .string(let id) = wire["id"], case .string(let status) = wire["status"] else { return nil }
        self.init(type: type, id: id, status: status, fields: wire)
    }
}

public struct Experimental_OpenResponsesExtensionEvent: Sendable, Equatable {
    public let type: String
    public let sequenceNumber: Double
    public let fields: JSONObject
    public init(type: String, sequenceNumber: Double, fields: JSONObject = [:]) {
        self.type = type
        self.sequenceNumber = sequenceNumber
        var values = fields
        values["type"] = .string(type)
        values["sequence_number"] = .number(sequenceNumber)
        self.fields = values
    }
    init?(wire: JSONObject) {
        guard case .string(let type) = wire["type"], case .number(let sequence) = wire["sequence_number"] else { return nil }
        self.init(type: type, sequenceNumber: sequence, fields: wire)
    }
}

public enum Experimental_OpenResponsesExtensionInputPart: Sendable {
    case toolCall(LanguageModelV4ToolCallPart)
    case toolResult(LanguageModelV4ToolResultPart)
}

public enum Experimental_OpenResponsesExtensionContentPart: Sendable, Equatable {
    case toolCall(LanguageModelV4ToolCall)
    case toolResult(LanguageModelV4ToolResult)
    case source(LanguageModelV4Source)
    case file(LanguageModelV4File)
    case reasoningFile(LanguageModelV4ReasoningFile)
    case toolApprovalRequest(LanguageModelV4ToolApprovalRequest)
    case custom(LanguageModelV4CustomContent)

    var content: LanguageModelV4Content {
        switch self {
        case .toolCall(let value): return .toolCall(value)
        case .toolResult(let value): return .toolResult(value)
        case .source(let value): return .source(value)
        case .file(let value): return .file(value)
        case .reasoningFile(let value): return .reasoningFile(value)
        case .toolApprovalRequest(let value): return .toolApprovalRequest(value)
        case .custom(let value): return .custom(value)
        }
    }
    var streamPart: LanguageModelV4StreamPart {
        switch self {
        case .toolCall(let value): return .toolCall(value)
        case .toolResult(let value): return .toolResult(value)
        case .source(let value): return .source(value)
        case .file(let value): return .file(value)
        case .reasoningFile(let value): return .reasoningFile(value)
        case .toolApprovalRequest(let value): return .toolApprovalRequest(value)
        case .custom(let value): return .custom(value)
        }
    }
    var isToolCall: Bool { if case .toolCall = self { return true }; return false }

    func referencing(extensionId: String, itemId: String, namespace: String) -> Self {
        func metadata(_ original: SharedV4ProviderMetadata?) -> SharedV4ProviderMetadata {
            var values = original ?? [:]
            var provider = values[namespace] ?? [:]
            provider["openResponsesExtension"] = ["id": .string(extensionId), "itemId": .string(itemId)]
            values[namespace] = provider
            return values
        }
        switch self {
        case .toolCall(let value): return .toolCall(.init(toolCallId: value.toolCallId, toolName: value.toolName, input: value.input, providerExecuted: value.providerExecuted, dynamic: value.dynamic, providerMetadata: metadata(value.providerMetadata)))
        case .toolResult(let value): return .toolResult(.init(toolCallId: value.toolCallId, toolName: value.toolName, result: value.result, isError: value.isError, preliminary: value.preliminary, dynamic: value.dynamic, providerMetadata: metadata(value.providerMetadata)))
        case .source(.url(let id, let url, let title, let original)): return .source(.url(id: id, url: url, title: title, providerMetadata: metadata(original)))
        case .source(.document(let id, let mediaType, let title, let filename, let original)): return .source(.document(id: id, mediaType: mediaType, title: title, filename: filename, providerMetadata: metadata(original)))
        case .file(let value): return .file(.init(mediaType: value.mediaType, data: value.data, providerMetadata: metadata(value.providerMetadata)))
        case .reasoningFile(let value): return .reasoningFile(.init(mediaType: value.mediaType, data: value.data, providerMetadata: metadata(value.providerMetadata)))
        case .toolApprovalRequest(let value): return .toolApprovalRequest(.init(approvalId: value.approvalId, toolCallId: value.toolCallId, providerMetadata: metadata(value.providerMetadata)))
        case .custom(let value): return .custom(.init(kind: value.kind, providerMetadata: metadata(value.providerMetadata)))
        }
    }
}

public enum Experimental_OpenResponsesExtensionStreamPart: Sendable, Equatable {
    case content(Experimental_OpenResponsesExtensionContentPart)
    case textStart(id: String, providerMetadata: SharedV4ProviderMetadata? = nil)
    case textDelta(id: String, delta: String, providerMetadata: SharedV4ProviderMetadata? = nil)
    case textEnd(id: String, providerMetadata: SharedV4ProviderMetadata? = nil, citations: [LanguageModelV4Citation]? = nil)
    case reasoningStart(id: String, providerMetadata: SharedV4ProviderMetadata? = nil)
    case reasoningDelta(id: String, delta: String, providerMetadata: SharedV4ProviderMetadata? = nil)
    case reasoningEnd(id: String, providerMetadata: SharedV4ProviderMetadata? = nil)
    case toolInputStart(id: String, toolName: String, providerMetadata: SharedV4ProviderMetadata? = nil, providerExecuted: Bool? = nil, dynamic: Bool? = nil, title: String? = nil, inputEncoding: LanguageModelV4ToolInputEncoding? = nil)
    case toolInputDelta(id: String, delta: String, providerMetadata: SharedV4ProviderMetadata? = nil)
    case toolInputEnd(id: String, providerMetadata: SharedV4ProviderMetadata? = nil)

    var value: LanguageModelV4StreamPart {
        switch self {
        case .content(let part): return part.streamPart
        case .textStart(let id, let metadata): return .textStart(id: id, providerMetadata: metadata)
        case .textDelta(let id, let delta, let metadata): return .textDelta(id: id, delta: delta, providerMetadata: metadata)
        case .textEnd(let id, let metadata, let citations): return .textEnd(id: id, providerMetadata: metadata, citations: citations)
        case .reasoningStart(let id, let metadata): return .reasoningStart(id: id, providerMetadata: metadata)
        case .reasoningDelta(let id, let delta, let metadata): return .reasoningDelta(id: id, delta: delta, providerMetadata: metadata)
        case .reasoningEnd(let id, let metadata): return .reasoningEnd(id: id, providerMetadata: metadata)
        case .toolInputStart(let id, let name, let metadata, let executed, let dynamic, let title, let encoding): return .toolInputStart(id: id, toolName: name, providerMetadata: metadata, providerExecuted: executed, dynamic: dynamic, title: title, inputEncoding: encoding)
        case .toolInputDelta(let id, let delta, let metadata): return .toolInputDelta(id: id, delta: delta, providerMetadata: metadata)
        case .toolInputEnd(let id, let metadata): return .toolInputEnd(id: id, providerMetadata: metadata)
        }
    }
    var signalsToolCall: Bool {
        switch self {
        case .content(let value): return value.isToolCall
        case .toolInputStart: return true
        default: return false
        }
    }
}

public struct Experimental_OpenResponsesExtensionStateKey<Value: Sendable>: Sendable, Hashable {
    let name: String
    public init(_ name: String) { self.name = name }
}

public struct Experimental_OpenResponsesExtensionStateEntry: Sendable {
    public let key: String
    public let value: any Sendable
}

public actor Experimental_OpenResponsesExtensionStreamState {
    private struct Slot {
        var value: any Sendable
        var previous: String?
        var next: String?
    }
    private var slots: [String: Slot] = [:]
    private var first: String?
    private var last: String?
    public init() {}
    public var count: Int { slots.count }
    public func value<Value: Sendable>(for key: Experimental_OpenResponsesExtensionStateKey<Value>) -> Value? { slots[key.name]?.value as? Value }
    public func contains<Value: Sendable>(_ key: Experimental_OpenResponsesExtensionStateKey<Value>) -> Bool { slots[key.name] != nil }
    public func set<Value: Sendable>(_ value: Value, for key: Experimental_OpenResponsesExtensionStateKey<Value>) {
        if slots[key.name] != nil { slots[key.name]?.value = value; return }
        slots[key.name] = Slot(value: value, previous: last, next: nil)
        if let last { slots[last]?.next = key.name } else { first = key.name }
        last = key.name
    }
    @discardableResult
    public func remove<Value: Sendable>(_ key: Experimental_OpenResponsesExtensionStateKey<Value>) -> Bool {
        guard let removed = slots.removeValue(forKey: key.name) else { return false }
        if let previous = removed.previous { slots[previous]?.next = removed.next } else { first = removed.next }
        if let next = removed.next { slots[next]?.previous = removed.previous } else { last = removed.previous }
        return true
    }
    public func keys() -> [String] { snapshot().map(\.key) }
    public func snapshot() -> [Experimental_OpenResponsesExtensionStateEntry] {
        var values: [Experimental_OpenResponsesExtensionStateEntry] = []
        var key = first
        while let current = key, let slot = slots[current] {
            values.append(.init(key: current, value: slot.value))
            key = slot.next
        }
        return values
    }
    public func removeAll() { slots.removeAll(); first = nil; last = nil }
}

public enum Experimental_OpenResponsesExtensionMode: Sendable { case generate, stream }
public enum Experimental_OpenResponsesEncodedInput: Sendable {
    case item(Experimental_OpenResponsesExtensionItem)
    case items([Experimental_OpenResponsesExtensionItem])
    var items: [Experimental_OpenResponsesExtensionItem] { switch self { case .item(let item): [item]; case .items(let items): items } }
}
public typealias Experimental_OpenResponsesToolEncoder = @Sendable (_ name: String, _ args: JSONObject) async throws -> JSONObject?
public typealias Experimental_OpenResponsesItemDecoder = @Sendable (_ item: Experimental_OpenResponsesExtensionItem, _ mode: Experimental_OpenResponsesExtensionMode) async throws -> [Experimental_OpenResponsesExtensionContentPart]?
public typealias Experimental_OpenResponsesInputEncoder = @Sendable (_ part: Experimental_OpenResponsesExtensionInputPart, _ tool: LanguageModelV4ProviderTool) async throws -> Experimental_OpenResponsesEncodedInput?
public typealias Experimental_OpenResponsesEventDecoder = @Sendable (_ event: Experimental_OpenResponsesExtensionEvent, _ state: Experimental_OpenResponsesExtensionStreamState) async throws -> [Experimental_OpenResponsesExtensionStreamPart]?

public protocol Experimental_OpenResponsesExtension: Sendable {
    var id: String { get }
    var toolType: Experimental_OpenResponsesNamespacedType? { get }
    var itemTypes: [Experimental_OpenResponsesNamespacedType]? { get }
    var eventTypes: [Experimental_OpenResponsesNamespacedType]? { get }
    var encodeTool: Experimental_OpenResponsesToolEncoder? { get }
    var encodeToolChoice: Experimental_OpenResponsesToolEncoder? { get }
    var decodeItem: Experimental_OpenResponsesItemDecoder? { get }
    var encodeInputItem: Experimental_OpenResponsesInputEncoder? { get }
    var decodeEvent: Experimental_OpenResponsesEventDecoder? { get }
}
public extension Experimental_OpenResponsesExtension {
    var toolType: Experimental_OpenResponsesNamespacedType? { nil }
    var itemTypes: [Experimental_OpenResponsesNamespacedType]? { nil }
    var eventTypes: [Experimental_OpenResponsesNamespacedType]? { nil }
    var encodeTool: Experimental_OpenResponsesToolEncoder? { nil }
    var encodeToolChoice: Experimental_OpenResponsesToolEncoder? { nil }
    var decodeItem: Experimental_OpenResponsesItemDecoder? { nil }
    var encodeInputItem: Experimental_OpenResponsesInputEncoder? { nil }
    var decodeEvent: Experimental_OpenResponsesEventDecoder? { nil }
}

public struct Experimental_OpenResponsesBareExtension: Sendable {
    public let id: String
    public let toolType: Experimental_OpenResponsesNamespacedType?
    public let itemTypes: [Experimental_OpenResponsesNamespacedType]?
    public let eventTypes: [Experimental_OpenResponsesNamespacedType]?
    public let bareToolType: String?
    public let bareItemTypes: [String]?
    public let bareEventTypes: [String]?
    public let encodeTool: Experimental_OpenResponsesToolEncoder?
    public let encodeToolChoice: Experimental_OpenResponsesToolEncoder?
    public let decodeItem: Experimental_OpenResponsesItemDecoder?
    public let encodeInputItem: Experimental_OpenResponsesInputEncoder?
    public let decodeEvent: Experimental_OpenResponsesEventDecoder?

    public init(id: String, toolType: Experimental_OpenResponsesNamespacedType? = nil,
                itemTypes: [Experimental_OpenResponsesNamespacedType]? = nil, eventTypes: [Experimental_OpenResponsesNamespacedType]? = nil,
                bareToolType: String? = nil, bareItemTypes: [String]? = nil, bareEventTypes: [String]? = nil,
                encodeTool: Experimental_OpenResponsesToolEncoder? = nil, encodeToolChoice: Experimental_OpenResponsesToolEncoder? = nil,
                decodeItem: Experimental_OpenResponsesItemDecoder? = nil, encodeInputItem: Experimental_OpenResponsesInputEncoder? = nil,
                decodeEvent: Experimental_OpenResponsesEventDecoder? = nil) {
        self.id = id; self.toolType = toolType; self.itemTypes = itemTypes; self.eventTypes = eventTypes
        self.bareToolType = bareToolType; self.bareItemTypes = bareItemTypes; self.bareEventTypes = bareEventTypes
        self.encodeTool = encodeTool; self.encodeToolChoice = encodeToolChoice; self.decodeItem = decodeItem
        self.encodeInputItem = encodeInputItem; self.decodeEvent = decodeEvent
    }
}

public enum Experimental_OpenResponsesExtensionRegistration: Sendable {
    case namespaced(any Experimental_OpenResponsesExtension)
    case bare(Experimental_OpenResponsesBareExtension)
}
