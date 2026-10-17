import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import OpenResponsesProvider

@Suite("Open Responses extension boundaries")
struct OpenResponsesExtensionTests {
    private func searchExtension() -> OpenResponsesTestExtension {
        var value = OpenResponsesTestExtension()
        value.toolType = "acme:search"
        value.itemTypes = ["acme:receipt", "acme:call", "acme:result"]
        value.encodeTool = { name, args in
            await Task.yield()
            var fields = args
            fields["name"] = .string(name)
            return fields
        }
        value.encodeToolChoice = { name, _ in ["name": .string(name)] }
        value.decodeItem = { item, _ in
            let call = try #require({ if case .string(let value) = item.fields["call_id"] { return value }; return nil }())
            let name = try #require({ if case .string(let value) = item.fields["name"] { return value }; return nil }())
            let input = String(decoding: try JSONEncoder().encode(item.fields["query"] ?? .null), as: UTF8.self)
            return [
                .toolCall(.init(toolCallId: call, toolName: name, input: input, providerExecuted: true, providerMetadata: ["acme": ["kept": true]])),
                .toolResult(.init(toolCallId: call, toolName: name, result: item.fields["result"] ?? .null))
            ]
        }
        value.encodeInputItem = { part, _ in
            switch part {
            case .toolCall(let call): return .item(.init(type: "acme:call", id: "call-" + call.toolCallId, status: "completed", fields: ["call_id": .string(call.toolCallId), "name": .string(call.toolName), "query": call.input]))
            case .toolResult(let result): return .item(.init(type: "acme:result", id: "result-" + result.toolCallId, status: "completed", fields: ["call_id": .string(result.toolCallId), "name": .string(result.toolName), "result": ["received": true]]))
            }
        }
        return value
    }

    @Test("registered tools, receipt decoding, references and original-wire replay stay coupled")
    func receiptReplay() async throws {
        let receipt: JSONValue = ["type": "acme:receipt", "id": "receipt", "status": "completed", "call_id": "call", "name": "search", "query": ["term": "docs"], "result": ["matches": 2], "opaque": ["signed": "unchanged"]]
        let endpoint = OpenResponsesTestEndpoint(openResponsesTestResponse(output: [receipt]))
        let provider = try openResponsesProvider(endpoint, extensions: [.namespaced(searchExtension())])
        let tool = LanguageModelV4Tool.provider(.init(id: "acme.search", name: "search", args: ["type": "forged", "collection": "docs"]))
        let result = try await provider("model").doGenerate(options: .init(prompt: openResponsesTestPrompt, tools: [tool], toolChoice: .tool(toolName: "search")))
        let body = try await endpoint.lastBody()
        #expect(body["tools"] == [["type": "acme:search", "name": "search", "collection": "docs"]])
        #expect(body["tool_choice"] == ["type": "acme:search", "name": "search"])
        #expect(result.content.count == 3)
        guard case .custom(let carrier) = result.content[0], case .toolCall(let call) = result.content[1], case .toolResult(let output) = result.content[2] else { Issue.record("Missing decoded receipt parts"); return }
        #expect(carrier.kind == "open-responses.extension-replay")
        #expect(carrier.providerMetadata?["acme"]?["openResponsesExtension"] == ["id": "acme.search", "item": receipt])
        #expect(call.providerMetadata?["acme"]?["kept"] == true)
        #expect(call.providerMetadata?["acme"]?["openResponsesExtension"] == ["id": "acme.search", "itemId": "receipt"])
        #expect(result.finishReason.unified == .toolCalls)
        let input = try JSONDecoder().decode(JSONValue.self, from: Data(call.input.utf8))
        let history: LanguageModelV4Prompt = [.assistant(content: [
            .custom(.init(kind: carrier.kind, providerOptions: carrier.providerMetadata)),
            .toolCall(.init(toolCallId: call.toolCallId, toolName: call.toolName, input: input, providerOptions: call.providerMetadata)),
            .toolResult(.init(toolCallId: output.toolCallId, toolName: output.toolName, output: .json(value: output.result), providerOptions: output.providerMetadata)),
            .custom(.init(kind: carrier.kind, providerOptions: carrier.providerMetadata))
        ], providerOptions: nil)]
        _ = try await provider("model").doGenerate(options: .init(prompt: history, tools: [tool]))
        #expect(try await endpoint.lastBody()["input"] == [receipt])
    }

    @Test("client-executed extension input codecs encode calls and results without receipts")
    func inputCodec() async throws {
        let endpoint = OpenResponsesTestEndpoint()
        let provider = try openResponsesProvider(endpoint, extensions: [.namespaced(searchExtension())])
        let tool = LanguageModelV4Tool.provider(.init(id: "acme.search", name: "search", args: [:]))
        let prompt: LanguageModelV4Prompt = [
            .assistant(content: [.toolCall(.init(toolCallId: "call", toolName: "search", input: ["term": "docs"]))], providerOptions: nil),
            .tool(content: [.toolResult(.init(toolCallId: "call", toolName: "search", output: .text(value: "result")))], providerOptions: nil)
        ]
        _ = try await provider("model").doGenerate(options: .init(prompt: prompt, tools: [tool]))
        #expect(try await endpoint.lastBody()["input"] == [
            ["type": "acme:call", "id": "call-call", "status": "completed", "call_id": "call", "name": "search", "query": ["term": "docs"]],
            ["type": "acme:result", "id": "result-call", "status": "completed", "call_id": "call", "name": "search", "result": ["received": true]]
        ])
    }

    @Test("invalid codec output is omitted with an unsupported history warning", arguments: ["empty", "wrong-type", "throw"])
    func rejectedInput(mode: String) async throws {
        var extensionValue = searchExtension()
        extensionValue.encodeInputItem = { _, _ in
            if mode == "throw" { throw InvalidArgumentError(argument: "codec", message: "cannot encode") }
            if mode == "empty" { return .items([]) }
            return .item(.init(type: "other:call", id: "item", status: "completed"))
        }
        let endpoint = OpenResponsesTestEndpoint()
        let provider = try openResponsesProvider(endpoint, extensions: [.namespaced(extensionValue)])
        let result = try await provider("model").doGenerate(options: .init(prompt: [.assistant(content: [.toolCall(.init(toolCallId: "call", toolName: "search", input: [:]))], providerOptions: nil)], tools: [.provider(.init(id: "acme.search", name: "search", args: [:]))]))
        #expect(try await endpoint.lastBody()["input"] == [])
        #expect(result.warnings == [.unsupported(feature: "provider-defined tool acme.search tool-call history", details: nil)])
    }

    @Test("tool and choice encoder failures omit only the unsupported payload", arguments: ["tool-nil", "tool-throw", "choice-nil", "choice-throw", "unregistered"])
    func omittedTool(mode: String) async throws {
        var extensionValue = searchExtension()
        if mode.hasPrefix("tool") {
            extensionValue.encodeTool = { _, _ in
                if mode == "tool-throw" { throw InvalidArgumentError(argument: "codec", message: "cannot encode") }
                return nil
            }
        } else if mode.hasPrefix("choice") {
            extensionValue.encodeToolChoice = { _, _ in
                if mode == "choice-throw" { throw InvalidArgumentError(argument: "codec", message: "cannot encode") }
                return nil
            }
        }
        let endpoint = OpenResponsesTestEndpoint()
        let provider = try openResponsesProvider(endpoint, extensions: [.namespaced(extensionValue)])
        let id = mode == "unregistered" ? "other.tool" : "acme.search"
        let result = try await provider("model").doGenerate(options: .init(prompt: [], tools: [.provider(.init(id: id, name: "search", args: [:]))], toolChoice: .tool(toolName: "search")))
        let body = try await endpoint.lastBody()
        #expect(body["tool_choice"] == nil)
        if mode.hasPrefix("choice") {
            #expect(body["tools"] == [["type": "acme:search", "name": "search"]])
            #expect(result.warnings == [.unsupported(feature: "tool choice for provider-defined tool acme.search", details: nil)])
        } else {
            #expect(body["tools"] == nil)
            #expect(result.warnings == [.unsupported(feature: "provider-defined tool \(id)", details: nil)])
        }
    }

    @Test("explicit bare codecs support source-only replay and asynchronous event decoding")
    func bareCodec() async throws {
        let bare = Experimental_OpenResponsesBareExtension(id: "acme.web", bareToolType: "web_search", bareItemTypes: ["web_search_call"], bareEventTypes: ["response.web_search_call.completed"],
            encodeTool: { name, _ in ["name": .string(name)] }, encodeToolChoice: { name, _ in ["name": .string(name)] },
            decodeItem: { _, _ in [.source(.url(id: "source", url: "https://example.com", title: "Source", providerMetadata: nil))] },
            decodeEvent: { _, _ in await Task.yield(); return [.content(.custom(.init(kind: "progress")))] })
        let item: JSONValue = ["type": "web_search_call", "id": "web", "status": "completed", "opaque": ["retained": true]]
        let endpoint = OpenResponsesTestEndpoint(openResponsesTestResponse(output: [item]))
        let provider = try openResponsesProvider(endpoint, extensions: [.bare(bare)])
        let tool = LanguageModelV4Tool.provider(.init(id: "acme.web", name: "lookup", args: [:]))
        let generated = try await provider("model").doGenerate(options: .init(prompt: [], tools: [tool], toolChoice: .tool(toolName: "lookup")))
        #expect(try await endpoint.lastBody()["tool_choice"] == ["type": "web_search", "name": "lookup"])
        guard case .custom(let carrier) = generated.content[0], case .source(.url(_, _, _, let metadata)) = generated.content[1] else { Issue.record("Missing source receipt"); return }
        #expect(metadata?["acme"]?["openResponsesExtension"] == ["id": "acme.web", "itemId": "web"])
        _ = try await provider("model").doGenerate(options: .init(prompt: [.assistant(content: [.custom(.init(kind: carrier.kind, providerOptions: carrier.providerMetadata))], providerOptions: nil)]))
        #expect(try await endpoint.lastBody()["input"] == [item])
        try await endpoint.setEvents([["type": "response.web_search_call.completed", "sequence_number": 0], ["type": "response.output_item.done", "item": item], ["type": "response.completed", "response": [:]]])
        let parts = try await openResponsesCollect(provider("model").doStream(options: .init(prompt: [])))
        #expect(parts.contains(.custom(.init(kind: "progress"))))
        #expect(parts.contains(.source(.url(id: "source", url: "https://example.com", title: "Source", providerMetadata: ["acme": ["openResponsesExtension": ["id": "acme.web", "itemId": "web"]]]))))
    }

    @Test("extension event state supports ordered Map operations and is isolated per stream")
    func streamState() async throws {
        let a = Experimental_OpenResponsesExtensionStateKey<Int>("a")
        let b = Experimental_OpenResponsesExtensionStateKey<Int>("b")
        let c = Experimental_OpenResponsesExtensionStateKey<Int>("c")
        var extensionValue = OpenResponsesTestExtension(id: "acme.state")
        extensionValue.eventTypes = ["acme:state"]
        extensionValue.decodeEvent = { event, state in
            let before = await state.snapshot().reduce(0) { $0 + (($1.value as? Int) ?? 0) }
            if event.fields["phase"] == "populate" {
                await state.set(1, for: a); await state.set(2, for: b); await state.set(3, for: c)
                await state.remove(b); await state.set(20, for: b); await state.set(10, for: a)
            } else { await state.removeAll() }
            let keys = await state.keys()
            let snapshot = await state.snapshot()
            let count = await state.count
            let present = await state.contains(a)
            let value = await state.value(for: a)
            return [.content(.custom(.init(kind: "state", providerMetadata: ["acme": ["before": .number(Double(before)), "count": .number(Double(count)), "keys": .array(keys.map(JSONValue.string)), "snapshotKeys": .array(snapshot.map { .string($0.key) }), "present": .bool(present), "value": value.map { .number(Double($0)) } ?? .null]])))]
        }
        let endpoint = OpenResponsesTestEndpoint()
        let provider = try openResponsesProvider(endpoint, extensions: [.namespaced(extensionValue)])
        try await endpoint.setEvents([["type": "acme:state", "sequence_number": 0, "phase": "populate"], ["type": "acme:state", "sequence_number": 1, "phase": "clear"]])
        let first = try await openResponsesCollect(provider("model").doStream(options: .init(prompt: [])))
        let states = first.compactMap { part -> SharedV4ProviderMetadata? in if case .custom(let value) = part { return value.providerMetadata }; return nil }
        #expect(states == [["acme": ["before": 0, "count": 3, "keys": ["a", "c", "b"], "snapshotKeys": ["a", "c", "b"], "present": true, "value": 10]], ["acme": ["before": 33, "count": 0, "keys": [], "snapshotKeys": [], "present": false, "value": .null]]])
        try await endpoint.setEvents([["type": "acme:state", "sequence_number": 0, "phase": "clear"]])
        let second = try await openResponsesCollect(provider("model").doStream(options: .init(prompt: [])))
        #expect(second.contains(.custom(.init(kind: "state", providerMetadata: ["acme": ["before": 0, "count": 0, "keys": [], "snapshotKeys": [], "present": false, "value": .null]]))))
    }

    @Test("decode failures propagate from generation and remain typed parts while streaming")
    func decoderFailures() async throws {
        var extensionValue = OpenResponsesTestExtension(id: "acme.failure")
        extensionValue.itemTypes = ["acme:item"]
        extensionValue.eventTypes = ["acme:event"]
        extensionValue.decodeItem = { _, _ in throw InvalidArgumentError(argument: "item-codec", message: "item rejected") }
        extensionValue.decodeEvent = { _, _ in throw InvalidArgumentError(argument: "event-codec", message: "event rejected") }
        let item: JSONValue = ["type": "acme:item", "id": "item", "status": "completed"]
        let endpoint = OpenResponsesTestEndpoint(openResponsesTestResponse(output: [item]))
        let provider = try openResponsesProvider(endpoint, extensions: [.namespaced(extensionValue)])
        await #expect(throws: InvalidArgumentError.self) { _ = try await provider("model").doGenerate(options: .init(prompt: [])) }
        try await endpoint.setEvents([["type": "acme:event", "sequence_number": 0], ["type": "response.output_item.done", "item": item], ["type": "response.completed", "response": [:]]])
        let parts = try await openResponsesCollect(provider("model").doStream(options: .init(prompt: [])))
        let arguments = parts.compactMap { part -> String? in if case .error(.error(let error)) = part { return (error as? InvalidArgumentError)?.argument }; return nil }
        #expect(arguments == ["event-codec", "item-codec"])
        guard case .finish(let reason, _, _) = parts.last else { Issue.record("Missing finish"); return }
        #expect(reason.unified == .stop)
    }

    @Test("invalid registrations fail at provider creation", arguments: ["id", "namespace", "tool-pair", "choice-pair", "item-pair", "input-pair", "empty-items", "event-pair", "empty-events", "no-capability", "bare-empty", "bare-colon", "core-tool", "core-item", "core-event", "duplicate"])
    func registrationRefusal(kind: String) throws {
        var value = OpenResponsesTestExtension()
        var registrations: [Experimental_OpenResponsesExtensionRegistration]
        switch kind {
        case "id": value.id = "invalid"; value.eventTypes = ["acme:event"]; value.decodeEvent = { _, _ in nil }; registrations = [.namespaced(value)]
        case "namespace": value.toolType = "other:tool"; value.encodeTool = { _, _ in [:] }; registrations = [.namespaced(value)]
        case "tool-pair": value.toolType = "acme:tool"; registrations = [.namespaced(value)]
        case "choice-pair": value.encodeToolChoice = { _, _ in [:] }; registrations = [.namespaced(value)]
        case "item-pair": value.itemTypes = ["acme:item"]; registrations = [.namespaced(value)]
        case "input-pair": value.encodeInputItem = { _, _ in nil }; registrations = [.namespaced(value)]
        case "empty-items": value.itemTypes = []; value.decodeItem = { _, _ in nil }; registrations = [.namespaced(value)]
        case "event-pair": value.eventTypes = ["acme:event"]; registrations = [.namespaced(value)]
        case "empty-events": value.eventTypes = []; value.decodeEvent = { _, _ in nil }; registrations = [.namespaced(value)]
        case "bare-empty": registrations = [.bare(.init(id: "acme.bare"))]
        case "bare-colon": registrations = [.bare(.init(id: "acme.bare", bareToolType: "acme:tool", encodeTool: { _, _ in [:] }))]
        case "core-tool": registrations = [.bare(.init(id: "acme.bare", bareToolType: "function", encodeTool: { _, _ in [:] }))]
        case "core-item": registrations = [.bare(.init(id: "acme.bare", bareItemTypes: ["message"], decodeItem: { _, _ in nil }))]
        case "core-event": registrations = [.bare(.init(id: "acme.bare", bareEventTypes: ["response.output_text.delta"], decodeEvent: { _, _ in nil }))]
        case "duplicate":
            value.id = "acme.first"; value.itemTypes = ["acme:item"]; value.decodeItem = { _, _ in nil }
            var second = value; second.id = "acme.second"
            registrations = [.namespaced(value), .namespaced(second)]
        default: registrations = [.namespaced(value)]
        }
        do {
            _ = try createOpenResponses(options: .init(url: openResponsesTestURL, name: "acme", experimentalExtensions: registrations))
            Issue.record("Expected registration refusal")
        } catch let error as InvalidArgumentError {
            #expect(error.argument == "experimentalExtensions")
            if kind == "duplicate" { #expect(error.message.contains("acme.first") && error.message.contains("acme.second") && error.message.contains("acme:item")) }
        }
    }
}
