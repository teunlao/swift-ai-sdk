import Foundation
import AISDKProvider
import AISDKProviderUtils

enum OpenAIParallelCalls {
    struct Metadata: Sendable {
        let itemId: String
        let toolCallId: String
        let toolName: String
        let input: String
        let index: Double
        let count: Double
        var key: Data { Data(toolCallId.utf8) }

        func matches(_ other: Metadata) -> Bool {
            itemId.utf8.elementsEqual(other.itemId.utf8) && toolCallId.utf8.elementsEqual(other.toolCallId.utf8)
                && toolName.utf8.elementsEqual(other.toolName.utf8) && input.utf8.elementsEqual(other.input.utf8)
                && count == other.count
        }
        var jsonValue: JSONValue { .object([
            "itemId": .string(itemId), "toolCallId": .string(toolCallId), "toolName": .string(toolName),
            "input": .string(input), "index": .number(index), "count": .number(count)
        ]) }
    }

    static func metadata(_ options: SharedV4ProviderOptions?, namespace: String) -> Metadata? {
        guard case .object(let value)? = options?[namespace]?["parallelToolCall"],
              case .string(let itemId)? = value["itemId"], case .string(let id)? = value["toolCallId"],
              case .string(let name)? = value["toolName"], case .string(let input)? = value["input"],
              case .number(let index)? = value["index"], case .number(let count)? = value["count"],
              index.isFinite && index.rounded(.towardZero) == index,
              count.isFinite && count.rounded(.towardZero) == count, index >= 0, count > index else { return nil }
        return Metadata(itemId: itemId, toolCallId: id, toolName: name, input: input, index: index, count: count)
    }

    static func isWrapper(_ name: String, tools: [LanguageModelV4FunctionTool]) -> Bool {
        name == "parallel" && !tools.contains { $0.name == "parallel" }
    }

    static func expand(_ call: LanguageModelV4ToolCall, itemId: String, tools: [LanguageModelV4FunctionTool], namespace: String) async throws -> [LanguageModelV4ToolCall]? {
        guard isWrapper(call.toolName, tools: tools),
              case .success(let parsed, _) = await safeParseJSON(ParseJSONOptions(text: call.input)),
              case .object(let object) = parsed, case .array(let uses)? = object["tool_uses"], !uses.isEmpty else { return nil }
        let names = Set(tools.map { Array($0.name.utf8) })
        let prefix = Array("functions.".utf8)
        var calls: [LanguageModelV4ToolCall] = []
        for (index, use) in uses.enumerated() {
            guard case .object(let value) = use, case .string(let recipient)? = value["recipient_name"],
                  recipient.utf8.starts(with: prefix), case .object(let parameters)? = value["parameters"] else { return nil }
            let name = String(decoding: recipient.utf8.dropFirst(prefix.count), as: UTF8.self)
            guard !name.isEmpty, names.contains(Array(name.utf8)) else { return nil }
            let metadata = Metadata(itemId: itemId, toolCallId: call.toolCallId, toolName: call.toolName, input: call.input, index: Double(index), count: Double(uses.count))
            calls.append(.init(
                toolCallId: "\(call.toolCallId)_\(index)", toolName: name,
                input: try openAIJSONStringify(.object(parameters)),
                providerMetadata: [namespace: ["parallelToolCall": metadata.jsonValue]]
            ))
        }
        return calls
    }

    struct ResultGroup {
        let metadata: Metadata
        let results: [LanguageModelV4ToolResultPart]
    }
    private final class Pending {
        let metadata: Metadata
        var results: [Double: LanguageModelV4ToolResultPart]
        var invalid = false
        init(metadata: Metadata, result: LanguageModelV4ToolResultPart) {
            self.metadata = metadata
            results = [metadata.index: result]
        }
    }
    static func completeGroups(_ prompt: LanguageModelV4Prompt, namespace: String) -> [Data: ResultGroup] {
        var pending: [Data: Pending] = [:]
        for message in prompt {
            guard case .tool(let parts, _) = message else { continue }
            for part in parts {
                guard case .toolResult(let result) = part, let metadata = metadata(result.providerOptions, namespace: namespace) else { continue }
                if let group = pending[metadata.key] {
                    if !group.metadata.matches(metadata) || group.results[metadata.index] != nil {
                        group.invalid = true
                    } else { group.results[metadata.index] = result }
                } else {
                    pending[metadata.key] = Pending(metadata: metadata, result: result)
                }
            }
        }
        var complete: [Data: ResultGroup] = [:]
        for (id, group) in pending where !group.invalid && Double(group.results.count) == group.metadata.count {
            let results = (0..<group.results.count).compactMap { group.results[Double($0)] }
            if results.count == group.results.count { complete[id] = ResultGroup(metadata: group.metadata, results: results) }
        }
        return complete
    }
}
