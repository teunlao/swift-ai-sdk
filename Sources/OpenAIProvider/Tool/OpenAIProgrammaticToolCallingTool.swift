import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct OpenAIProgrammaticToolCallingInput: Codable, Sendable, Equatable {
    public let code: String
    public let fingerprint: String

    public init(code: String, fingerprint: String) {
        self.code = code
        self.fingerprint = fingerprint
    }
}

public struct OpenAIProgrammaticToolCallingOutput: Codable, Sendable, Equatable {
    public enum Status: String, Codable, Sendable { case completed, incomplete }
    public let result: String
    public let status: Status

    public init(result: String, status: Status) {
        self.result = result
        self.status = status
    }
}

private let programInputJSONSchema: JSONValue = .object([
    "type": .string("object"), "additionalProperties": .bool(false), "required": .array([.string("code"), .string("fingerprint")]),
    "properties": .object(["code": .object(["type": .string("string")]), "fingerprint": .object(["type": .string("string")])])
])
private let programOutputJSONSchema: JSONValue = .object([
    "type": .string("object"), "additionalProperties": .bool(false), "required": .array([.string("result"), .string("status")]),
    "properties": .object([
        "result": .object(["type": .string("string")]),
        "status": .object(["type": .string("string"), "enum": .array([.string("completed"), .string("incomplete")])])
    ])
])
public let openaiProgrammaticToolCallingInputSchema = openAIToolSchema(OpenAIProgrammaticToolCallingInput.self, programInputJSONSchema)
public let openaiProgrammaticToolCallingOutputSchema = openAIToolSchema(OpenAIProgrammaticToolCallingOutput.self, programOutputJSONSchema)
private let programmaticToolCallingFactory = createProviderExecutedToolFactory(
    id: "openai.programmatic_tool_calling", name: "programmatic_tool_calling",
    inputSchema: openAIToolSchema(programInputJSONSchema), outputSchema: openAIToolSchema(programOutputJSONSchema),
    supportsDeferredResults: true
)

public func openaiProgrammaticToolCallingTool() -> Tool {
    programmaticToolCallingFactory(.init()).withProviderToolCaller(ProviderToolCaller { providerOptions in
        var options = providerOptions ?? [:]
        var openai: [String: JSONValue]
        if case .object(let value)? = options["openai"] { openai = value } else { openai = [:] }
        let existing: [JSONValue]
        if case .array(let value)? = openai["allowedCallers"] { existing = value } else { existing = [] }
        var seen: Set<Data> = []
        var callers: [JSONValue] = []
        for caller in existing + [.string("programmatic")] {
            if case .string(let name) = caller, !seen.insert(Data(name.utf8)).inserted { continue }
            callers.append(caller)
        }
        openai["allowedCallers"] = .array(callers)
        options["openai"] = .object(openai)
        return options
    })
}
