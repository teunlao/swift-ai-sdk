import AISDKProvider

struct OpenResponsesExtensionEntry: Sendable {
    let id: String
    let namespacedToolType: String?
    let namespacedItemTypes: [String]?
    let namespacedEventTypes: [String]?
    let bareToolType: String?
    let bareItemTypes: [String]?
    let bareEventTypes: [String]?
    let allowsBare: Bool
    let encodeTool: Experimental_OpenResponsesToolEncoder?
    let encodeChoice: Experimental_OpenResponsesToolEncoder?
    let decodeItem: Experimental_OpenResponsesItemDecoder?
    let encodeInput: Experimental_OpenResponsesInputEncoder?
    let decodeEvent: Experimental_OpenResponsesEventDecoder?
    var toolType: String? { namespacedToolType ?? bareToolType }
    var itemTypes: [String] { (namespacedItemTypes ?? []) + (bareItemTypes ?? []) }

    init(_ registration: Experimental_OpenResponsesExtensionRegistration) {
        switch registration {
        case .namespaced(let value):
            id = value.id; namespacedToolType = value.toolType?.rawValue
            namespacedItemTypes = value.itemTypes?.map(\.rawValue); namespacedEventTypes = value.eventTypes?.map(\.rawValue)
            bareToolType = nil; bareItemTypes = nil; bareEventTypes = nil; allowsBare = false
            encodeTool = value.encodeTool; encodeChoice = value.encodeToolChoice
            decodeItem = value.decodeItem; encodeInput = value.encodeInputItem; decodeEvent = value.decodeEvent
        case .bare(let value):
            id = value.id; namespacedToolType = value.toolType?.rawValue
            namespacedItemTypes = value.itemTypes?.map(\.rawValue); namespacedEventTypes = value.eventTypes?.map(\.rawValue)
            bareToolType = value.bareToolType; bareItemTypes = value.bareItemTypes; bareEventTypes = value.bareEventTypes; allowsBare = true
            encodeTool = value.encodeTool; encodeChoice = value.encodeToolChoice
            decodeItem = value.decodeItem; encodeInput = value.encodeInputItem; decodeEvent = value.decodeEvent
        }
    }
}

struct OpenResponsesExtensionRegistry: Sendable {
    struct Tool: Sendable {
        let owner: OpenResponsesExtensionEntry
        let type: String
        let encode: Experimental_OpenResponsesToolEncoder
    }
    struct Item: Sendable {
        let owner: OpenResponsesExtensionEntry
        let decode: Experimental_OpenResponsesItemDecoder
    }
    struct Event: Sendable {
        let owner: OpenResponsesExtensionEntry
        let decode: Experimental_OpenResponsesEventDecoder
    }
    let byId: [String: OpenResponsesExtensionEntry]
    let byProviderToolId: [String: Tool]
    let byToolType: [String: Tool]
    let byItemType: [String: Item]
    let byEventType: [String: Event]

    init(_ registrations: [Experimental_OpenResponsesExtensionRegistration]) throws {
        var ids: [String: OpenResponsesExtensionEntry] = [:]
        var providers: [String: Tool] = [:]
        var tools: [String: Tool] = [:]
        var items: [String: Item] = [:]
        var events: [String: Event] = [:]
        for registration in registrations {
            let entry = OpenResponsesExtensionEntry(registration)
            guard let dot = entry.id.firstIndex(of: "."), dot != entry.id.startIndex else { throw Self.invalid("Open Responses extension ID \(entry.id) must use <implementor>.<extension> format.") }
            let namespace = String(entry.id[..<dot])
            if let existing = ids[entry.id] { throw Self.duplicate(entry, field: "id", key: entry.id, existing: existing) }
            ids[entry.id] = entry
            let hasBare = entry.bareToolType != nil || entry.bareItemTypes != nil || entry.bareEventTypes != nil
            guard hasBare == entry.allowsBare else { throw Self.invalid("Open Responses extension \(entry.id) must set allowBareTypes to true exactly when registering bare types.") }
            guard entry.namespacedToolType == nil || entry.bareToolType == nil else { throw Self.invalid("Open Responses extension \(entry.id) cannot provide toolType and bareToolType together.") }
            let toolField = entry.bareToolType != nil ? "bareToolType" : "toolType"
            guard (entry.toolType != nil) == (entry.encodeTool != nil) else { throw Self.invalid("Open Responses extension \(entry.id) must provide \(toolField) and encodeTool together.") }
            guard entry.encodeChoice == nil || entry.encodeTool != nil else { throw Self.invalid("Open Responses extension \(entry.id) cannot provide encodeToolChoice without a tool type and encodeTool.") }
            if let type = entry.toolType, let encoder = entry.encodeTool {
                try Self.validate(type, namespaced: entry.namespacedToolType != nil, namespace: namespace, core: Self.coreTools, entry: entry, field: toolField)
                if let existing = providers[entry.id] { throw Self.duplicate(entry, field: "provider-tool id", key: entry.id, existing: existing.owner) }
                if let existing = tools[type] { throw Self.duplicate(entry, field: "tool type", key: type, existing: existing.owner) }
                let capability = Tool(owner: entry, type: type, encode: encoder)
                providers[entry.id] = capability
                tools[type] = capability
            }
            let hasItems = entry.namespacedItemTypes != nil || entry.bareItemTypes != nil
            guard hasItems == (entry.decodeItem != nil) else { throw Self.invalid("Open Responses extension \(entry.id) must provide itemTypes or bareItemTypes together with decodeItem.") }
            guard entry.encodeInput == nil || entry.decodeItem != nil else { throw Self.invalid("Open Responses extension \(entry.id) cannot provide encodeInputItem without itemTypes or bareItemTypes and decodeItem.") }
            if let decoder = entry.decodeItem {
                guard !entry.itemTypes.isEmpty else { throw Self.invalid("Open Responses extension \(entry.id) must register at least one item type.") }
                for type in entry.namespacedItemTypes ?? [] {
                    try Self.validate(type, namespaced: true, namespace: namespace, core: Self.coreItems, entry: entry, field: "itemTypes")
                    if let existing = items[type] { throw Self.duplicate(entry, field: "item type", key: type, existing: existing.owner) }
                    items[type] = Item(owner: entry, decode: decoder)
                }
                for type in entry.bareItemTypes ?? [] {
                    try Self.validate(type, namespaced: false, namespace: namespace, core: Self.coreItems, entry: entry, field: "bareItemTypes")
                    if let existing = items[type] { throw Self.duplicate(entry, field: "item type", key: type, existing: existing.owner) }
                    items[type] = Item(owner: entry, decode: decoder)
                }
            }
            let hasEvents = entry.namespacedEventTypes != nil || entry.bareEventTypes != nil
            guard hasEvents == (entry.decodeEvent != nil) else { throw Self.invalid("Open Responses extension \(entry.id) must provide eventTypes or bareEventTypes together with decodeEvent.") }
            if let decoder = entry.decodeEvent {
                let types = (entry.namespacedEventTypes ?? []) + (entry.bareEventTypes ?? [])
                guard !types.isEmpty else { throw Self.invalid("Open Responses extension \(entry.id) must register at least one event type.") }
                for type in entry.namespacedEventTypes ?? [] {
                    try Self.validate(type, namespaced: true, namespace: namespace, core: Self.coreEvents, entry: entry, field: "eventTypes")
                    if let existing = events[type] { throw Self.duplicate(entry, field: "event type", key: type, existing: existing.owner) }
                    events[type] = Event(owner: entry, decode: decoder)
                }
                for type in entry.bareEventTypes ?? [] {
                    try Self.validate(type, namespaced: false, namespace: namespace, core: Self.coreEvents, entry: entry, field: "bareEventTypes")
                    if let existing = events[type] { throw Self.duplicate(entry, field: "event type", key: type, existing: existing.owner) }
                    events[type] = Event(owner: entry, decode: decoder)
                }
            }
            guard entry.encodeTool != nil || entry.decodeItem != nil || entry.decodeEvent != nil else { throw Self.invalid("Open Responses extension \(entry.id) must register a tool, item, or event capability.") }
        }
        byId = ids; byProviderToolId = providers; byToolType = tools; byItemType = items; byEventType = events
    }

    func decode(_ item: Experimental_OpenResponsesExtensionItem, mode: Experimental_OpenResponsesExtensionMode, namespace: String) async throws -> [Experimental_OpenResponsesExtensionContentPart]? {
        guard let capability = byItemType[item.type] else { return nil }
        guard let decoded = try await capability.decode(item, mode) else { return nil }
        let carrier = Experimental_OpenResponsesExtensionContentPart.custom(.init(kind: "open-responses.extension-replay", providerMetadata: [namespace: ["openResponsesExtension": ["id": .string(capability.owner.id), "item": .object(item.fields)]]]))
        return [carrier] + decoded.map { $0.referencing(extensionId: capability.owner.id, itemId: item.id, namespace: namespace) }
    }

    private static func invalid(_ message: String) -> InvalidArgumentError { .init(argument: "experimentalExtensions", message: message) }
    private static func duplicate(_ entry: OpenResponsesExtensionEntry, field: String, key: String, existing: OpenResponsesExtensionEntry) -> InvalidArgumentError {
        invalid("Open Responses extension \(entry.id) cannot register \(field) \(key) because it is already registered by \(existing.id).")
    }
    private static func validate(_ type: String, namespaced: Bool, namespace: String, core: Set<String>, entry: OpenResponsesExtensionEntry, field: String) throws {
        if namespaced {
            guard let colon = type.firstIndex(of: ":"), colon != type.startIndex, String(type[..<colon]) == namespace else {
                throw invalid("Open Responses extension \(entry.id) has invalid \(field) value \(type). Extension wire types must use the \(namespace): namespace.")
            }
        } else {
            guard !type.isEmpty, !type.contains(":") else {
                throw invalid("Open Responses extension \(entry.id) has invalid \(field) value \(type). Bare extension wire types must be non-empty and must not contain a colon.")
            }
            guard !core.contains(type) else { throw invalid("Open Responses extension \(entry.id) cannot register core \(field) value \(type).") }
        }
    }
    private static let coreTools: Set<String> = ["allowed_tools", "function"]
    private static let coreItems: Set<String> = ["function_call", "function_call_output", "item_reference", "message", "reasoning"]
    private static let coreEvents: Set<String> = [
        "error", "response.completed", "response.content_part.added", "response.content_part.done", "response.created", "response.failed",
        "response.function_call_arguments.delta", "response.function_call_arguments.done", "response.in_progress", "response.incomplete",
        "response.output_item.added", "response.output_item.done", "response.output_text.delta", "response.output_text.done",
        "response.reasoning_summary_part.added", "response.reasoning_summary_part.done", "response.reasoning_summary_text.delta",
        "response.reasoning_summary_text.done", "response.reasoning_text.delta", "response.refusal.delta", "response.refusal.done"
    ]
}
