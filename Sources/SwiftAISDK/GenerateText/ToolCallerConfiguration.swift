import Foundation
import AISDKProvider
import AISDKProviderUtils

public typealias ToolCallers = [String: [String]]

private let directToolCall = "AI_SDK_DIRECT_TOOL_CALL"

func resolveToolCallers(tools: ToolSet?, callers: ToolCallers?) throws -> ToolCallers? {
    guard let tools, let callers else { return nil }
    let names = Set(tools.keys.map { Data($0.utf8) })
    let value = JSONValue.object(callers.mapValues { .array($0.map(JSONValue.string)) })
    for (name, callerNames) in callers {
        guard names.contains(Data(name.utf8)) else {
            throw InvalidArgumentError(parameter: "experimental_toolCallers", value: value, message: "unknown tool \"\(name)\".")
        }
        for caller in callerNames {
            if caller.utf8.elementsEqual(directToolCall.utf8) { continue }
            guard names.contains(Data(caller.utf8)), tools[caller]?.providerToolCaller != nil else {
                throw InvalidArgumentError(parameter: "experimental_toolCallers", value: value, message: "tool \"\(name)\" contains an invalid caller.")
            }
        }
    }
    return callers
}

struct PreparedCallerTools {
    let executionTools: ToolSet?
    let modelTools: ToolSet?
}

func prepareCallerTools(tools: ToolSet?, callers: ToolCallers?) -> PreparedCallerTools {
    guard let tools, let callers else {
        return PreparedCallerTools(executionTools: tools, modelTools: tools)
    }
    var executionTools = tools
    var modelTools = tools
    let names = Set(tools.keys.map { Data($0.utf8) })
    for (name, callerNames) in callers {
        guard names.contains(Data(name.utf8)), var preparedTool = executionTools[name] else { continue }
        var directlyAvailable = false
        var providerAvailable = false
        for callerName in callerNames {
            if callerName.utf8.elementsEqual(directToolCall.utf8) {
                directlyAvailable = true
                continue
            }
            guard names.contains(Data(callerName.utf8)), let caller = executionTools[callerName]?.providerToolCaller else { continue }
            providerAvailable = true
            preparedTool = preparedTool.withProviderOptions(caller.prepareProviderOptions(preparedTool.providerOptions))
        }
        executionTools[name] = preparedTool
        if directlyAvailable || providerAvailable {
            modelTools[name] = preparedTool
        } else {
            modelTools.removeValue(forKey: name)
        }
    }
    return PreparedCallerTools(executionTools: executionTools, modelTools: modelTools)
}
