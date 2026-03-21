import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import OpenAIProvider

@Suite("OpenAIResponses fixture scenarios")
struct OpenAIResponsesFixtureTests {
    private let responsesURL = URL(string: "https://api.openai.com/v1/responses")!
    private let samplePrompt: LanguageModelV3Prompt = [
        .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
    ]

    private final class SequentialIdGenerator: @unchecked Sendable {
        private let lock = NSLock()
        private var counter = 0

        func next() -> String {
            lock.lock()
            defer { lock.unlock() }
            let value = counter
            counter += 1
            return "generated-\(value)"
        }
    }

    private actor RequestCapture {
        private(set) var request: URLRequest?

        func store(_ request: URLRequest) {
            self.request = request
        }

        func current() -> URLRequest? {
            request
        }
    }

    private func fixturesDirectory() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("external/vercel-ai-sdk/packages/openai/src/responses/__fixtures__")
    }

    private func loadJSONFixture(_ name: String) throws -> Any {
        let url = fixturesDirectory().appendingPathComponent("\(name).json")
        let data = try Data(contentsOf: url)
        return try JSONSerialization.jsonObject(with: data)
    }

    private func loadChunksFixture(_ name: String) throws -> [String] {
        let url = fixturesDirectory().appendingPathComponent("\(name).chunks.txt")
        let text = try String(contentsOf: url, encoding: .utf8)
        var chunks = text
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { "data: \($0)\n\n" }
        chunks.append("data: [DONE]\n\n")
        return chunks
    }

    private func decodeRequestBody(_ request: URLRequest?) -> [String: Any]? {
        guard let data = request?.httpBody else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func decodeToolInput(_ input: String) -> [String: Any]? {
        guard let data = input.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func makeModel(
        modelId: OpenAIResponsesModelId,
        fetch: @escaping FetchFunction
    ) -> OpenAIResponsesLanguageModel {
        let generator = SequentialIdGenerator()
        return OpenAIResponsesLanguageModel(
            modelId: modelId,
            config: OpenAIConfig(
                provider: "openai.responses",
                url: { _ in "https://api.openai.com/v1/responses" },
                headers: { [:] },
                fetch: fetch,
                generateId: { generator.next() },
                fileIdPrefixes: ["file-"]
            )
        )
    }

    private func makeJSONFetch(
        fixture name: String,
        capture: RequestCapture? = nil
    ) throws -> FetchFunction {
        let fixture = try loadJSONFixture(name)
        let responseData = try JSONSerialization.data(withJSONObject: fixture)
        let response = HTTPURLResponse(
            url: responsesURL,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        return { request in
            if let capture {
                await capture.store(request)
            }
            return FetchResponse(body: .data(responseData), urlResponse: response)
        }
    }

    private func makeStreamFetch(
        fixture name: String,
        capture: RequestCapture? = nil
    ) throws -> FetchFunction {
        let chunks = try loadChunksFixture(name)
        let response = HTTPURLResponse(
            url: responsesURL,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!

        return { request in
            if let capture {
                await capture.store(request)
            }

            let stream = AsyncThrowingStream<Data, Error> { continuation in
                for chunk in chunks {
                    continuation.yield(Data(chunk.utf8))
                }
                continuation.finish()
            }

            return FetchResponse(body: .stream(stream), urlResponse: response)
        }
    }

    private func makeShellTool() -> LanguageModelV3Tool {
        .provider(.init(
            id: "openai.shell",
            name: "shell",
            args: [
                "environment": .object([
                    "type": .string("containerAuto")
                ])
            ]
        ))
    }

    private func makeLocalShellTool() -> LanguageModelV3Tool {
        .provider(.init(
            id: "openai.local_shell",
            name: "shell",
            args: [:]
        ))
    }

    private func makePlainShellTool() -> LanguageModelV3Tool {
        .provider(.init(
            id: "openai.shell",
            name: "shell",
            args: [:]
        ))
    }

    private func makeMCPTool() -> LanguageModelV3Tool {
        .provider(.init(
            id: "openai.mcp",
            name: "MCP",
            args: [
                "serverLabel": .string("zip1"),
                "serverUrl": .string("https://zip1.io/mcp"),
                "serverDescription": .string("Link shortener"),
                "requireApproval": .string("always")
            ]
        ))
    }

    private func makeDefaultMCPTool() -> LanguageModelV3Tool {
        .provider(.init(
            id: "openai.mcp",
            name: "MCP",
            args: [
                "serverLabel": .string("dmcp"),
                "serverUrl": .string("https://mcp.exa.ai/mcp"),
                "serverDescription": .string("A web-search API for AI agents")
            ]
        ))
    }

    private func makeWebSearchTool() -> LanguageModelV3Tool {
        .provider(.init(
            id: "openai.web_search",
            name: "webSearch",
            args: [:]
        ))
    }

    private func makeCodeInterpreterTool() -> LanguageModelV3Tool {
        .provider(.init(
            id: "openai.code_interpreter",
            name: "codeExecution",
            args: [:]
        ))
    }

    private func makeCalculatorTool() -> LanguageModelV3Tool {
        .function(.init(
            name: "calculator",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "a": .object([
                        "type": .string("number"),
                        "description": .string("First operand.")
                    ]),
                    "b": .object([
                        "type": .string("number"),
                        "description": .string("Second operand.")
                    ]),
                    "op": .object([
                        "type": .string("string"),
                        "enum": .array([
                            .string("add"),
                            .string("subtract"),
                            .string("multiply"),
                            .string("divide")
                        ]),
                        "default": .string("add"),
                        "description": .string("Arithmetic operation to perform.")
                    ])
                ]),
                "required": .array([
                    .string("a"),
                    .string("b"),
                    .string("op")
                ]),
                "additionalProperties": .bool(false)
            ]),
            description: "A minimal calculator for basic arithmetic. Call it once per step."
        ))
    }

    private func makeMCPApprovalTurn2Prompt() -> LanguageModelV3Prompt {
        [
            .user(
                content: [.text(.init(text: "shorten ai-sdk.dev"))],
                providerOptions: nil
            ),
            .assistant(
                content: [
                    .toolCall(.init(
                        toolCallId: "mcpr_04f6b17429cf2b02006949a6712b1081968b3c7a72dec695d8",
                        toolName: "mcp.create_short_url",
                        input: .object([
                            "url": .string("https://ai-sdk.dev/")
                        ]),
                        providerExecuted: true,
                        providerOptions: nil
                    ))
                ],
                providerOptions: nil
            ),
            .tool(
                content: [
                    .toolApprovalResponse(.init(
                        approvalId: "mcpr_04f6b17429cf2b02006949a6712b1081968b3c7a72dec695d8",
                        approved: false,
                        reason: nil,
                        providerOptions: nil
                    ))
                ],
                providerOptions: nil
            )
        ]
    }

    private func makeMCPApprovalTurn3Prompt() -> LanguageModelV3Prompt {
        [
            .user(
                content: [.text(.init(text: "shorten ai-sdk.dev"))],
                providerOptions: nil
            ),
            .assistant(
                content: [
                    .toolCall(.init(
                        toolCallId: "mcpr_04f6b17429cf2b02006949a6712b1081968b3c7a72dec695d8",
                        toolName: "mcp.create_short_url",
                        input: .object([
                            "url": .string("https://ai-sdk.dev/")
                        ]),
                        providerExecuted: true,
                        providerOptions: nil
                    ))
                ],
                providerOptions: nil
            ),
            .tool(
                content: [
                    .toolApprovalResponse(.init(
                        approvalId: "mcpr_04f6b17429cf2b02006949a6712b1081968b3c7a72dec695d8",
                        approved: false,
                        reason: nil,
                        providerOptions: nil
                    ))
                ],
                providerOptions: nil
            ),
            .assistant(
                content: [
                    .text(.init(text: "The tool was not approved."))
                ],
                providerOptions: nil
            ),
            .user(
                content: [.text(.init(text: "try again"))],
                providerOptions: nil
            )
        ]
    }

    private func makeMCPApprovalTurn4Prompt() -> LanguageModelV3Prompt {
        [
            .user(
                content: [.text(.init(text: "shorten ai-sdk.dev"))],
                providerOptions: nil
            ),
            .assistant(
                content: [
                    .toolCall(.init(
                        toolCallId: "mcpr_04f6b17429cf2b02006949a68bf5808196b6f2008a315c9aa4",
                        toolName: "mcp.create_short_url",
                        input: .object([
                            "url": .string("https://ai-sdk.dev/")
                        ]),
                        providerExecuted: true,
                        providerOptions: nil
                    ))
                ],
                providerOptions: nil
            ),
            .tool(
                content: [
                    .toolApprovalResponse(.init(
                        approvalId: "mcpr_04f6b17429cf2b02006949a68bf5808196b6f2008a315c9aa4",
                        approved: true,
                        reason: nil,
                        providerOptions: nil
                    ))
                ],
                providerOptions: nil
            )
        ]
    }

    private func collectStreamParts(
        _ result: LanguageModelV3StreamResult
    ) async throws -> [LanguageModelV3StreamPart] {
        var parts: [LanguageModelV3StreamPart] = []
        for try await part in result.stream {
            parts.append(part)
        }
        return parts
    }

    private func collectText(_ parts: [LanguageModelV3StreamPart]) -> String {
        parts.compactMap { part in
            if case .textDelta(_, let delta, _) = part {
                return delta
            }
            return nil
        }.joined()
    }

    @Test("doGenerate decodes shell skill fixture")
    func doGenerateMatchesShellSkillsFixture() async throws {
        let capture = RequestCapture()
        let model = try makeModel(
            modelId: "gpt-5.2",
            fetch: makeJSONFetch(fixture: "openai-shell-skills.1", capture: capture)
        )

        let result = try await model.doGenerate(options: .init(
            prompt: samplePrompt,
            tools: [makeShellTool()]
        ))

        let toolCalls = result.content.compactMap { content -> LanguageModelV3ToolCall? in
            if case .toolCall(let call) = content { return call }
            return nil
        }
        let toolResults = result.content.compactMap { content -> LanguageModelV3ToolResult? in
            if case .toolResult(let result) = content { return result }
            return nil
        }
        let textParts = result.content.compactMap { content -> LanguageModelV3Text? in
            if case .text(let text) = content { return text }
            return nil
        }

        #expect(toolCalls.count == 2)
        #expect(toolResults.count == 2)
        #expect(textParts.count == 1)
        #expect(result.finishReason.unified == .stop)
        #expect(result.providerMetadata?["openai"]?["responseId"] == .string("resp_01b6b3812d7541bd00698f7197d5bc81969c3d2a134af0cb66"))

        #expect(toolCalls[0].toolCallId == "call_KPDqtcOSQeaV3UKcb30ZfeqD")
        #expect(toolCalls[0].toolName == "shell")
        #expect(toolCalls[0].providerExecuted == true)
        #expect(toolCalls[0].providerMetadata?["openai"]?["itemId"] == .string("sh_01b6b3812d7541bd00698f71a351a08196acffc9543b76a179"))
        #expect(toolCalls[1].toolCallId == "call_5RmHRaiiFm8rPqUBqqXjG4WA")
        #expect(toolCalls[1].providerExecuted == true)
        #expect(toolCalls[1].providerMetadata?["openai"]?["itemId"] == .string("sh_01b6b3812d7541bd00698f71a4c0e88196b89199531ef2ee07"))

        #expect(toolResults[0].toolCallId == "call_KPDqtcOSQeaV3UKcb30ZfeqD")
        #expect(toolResults[1].toolCallId == "call_5RmHRaiiFm8rPqUBqqXjG4WA")
        if case .object(let firstPayload) = toolResults[0].result,
           case .array(let output)? = firstPayload["output"],
           case .object(let firstLine) = output.first {
            #expect(firstLine["stdout"] == .string("/home/oai/skills/island-rescue-ab6238cd308ce72a5ae69fd3ba1e3aeb:\nSKILL.md\n"))
        } else {
            Issue.record("Expected shell tool output payload for first shell result")
        }

        #expect(textParts[0].text.contains("Build a STOP huge signal"))
        #expect(textParts[0].providerMetadata?["openai"]?["itemId"] == JSONValue.string("msg_01b6b3812d7541bd00698f71a5de488196b6ae435d1a54ed9c"))

        guard let requestBody = decodeRequestBody(await capture.current()),
              let tools = requestBody["tools"] as? [[String: Any]],
              let environment = tools.first?["environment"] as? [String: Any] else {
            Issue.record("Missing request body for shell-skills fixture")
            return
        }

        #expect(requestBody["model"] as? String == "gpt-5.2")
        #expect(environment["type"] as? String == "container_auto")
    }

    @Test("doGenerate decodes local shell fixture")
    func doGenerateDecodesLocalShellFixture() async throws {
        let capture = RequestCapture()
        let model = try makeModel(
            modelId: "gpt-5-codex",
            fetch: makeJSONFetch(fixture: "openai-local-shell-tool.1", capture: capture)
        )

        let result = try await model.doGenerate(options: .init(
            prompt: samplePrompt,
            tools: [makeLocalShellTool()]
        ))

        let reasoningParts = result.content.compactMap { content -> LanguageModelV3Reasoning? in
            if case .reasoning(let reasoning) = content { return reasoning }
            return nil
        }
        let toolCalls = result.content.compactMap { content -> LanguageModelV3ToolCall? in
            if case .toolCall(let call) = content { return call }
            return nil
        }
        let textParts = result.content.compactMap { content -> LanguageModelV3Text? in
            if case .text(let text) = content { return text }
            return nil
        }
        let toolResults = result.content.compactMap { content -> LanguageModelV3ToolResult? in
            if case .toolResult(let toolResult) = content { return toolResult }
            return nil
        }

        #expect(reasoningParts.count == 1)
        #expect(toolCalls.count == 1)
        #expect(toolResults.isEmpty)
        #expect(textParts.isEmpty)
        #expect(result.finishReason.unified == .stop)
        #expect(result.providerMetadata?["openai"]?["responseId"] == .string("resp_68da74aaae58819ca776fbd20244e8df0fdbc19a07110799"))

        #expect(toolCalls[0].toolCallId == "call_XWgeTylovOiS8xLNz2TONOgO")
        #expect(toolCalls[0].toolName == "shell")
        #expect(toolCalls[0].providerExecuted == nil)
        #expect(toolCalls[0].providerMetadata?["openai"]?["itemId"] == .string("lsh_68da74abdaec819c9aa19c124308f4600fdbc19a07110799"))

        guard let toolInput = decodeToolInput(toolCalls[0].input),
              let action = toolInput["action"] as? [String: Any],
              let command = action["command"] as? [String],
              let env = action["env"] as? [String: Any] else {
            Issue.record("Expected local shell action payload")
            return
        }

        #expect(action["type"] as? String == "exec")
        #expect(command == ["ls"])
        #expect(action["working_directory"] as? String == "/root")
        #expect(env.isEmpty)

        guard let requestBody = decodeRequestBody(await capture.current()),
              let tools = requestBody["tools"] as? [[String: Any]],
              let firstTool = tools.first else {
            Issue.record("Missing request body for local shell fixture")
            return
        }

        #expect(requestBody["model"] as? String == "gpt-5-codex")
        #expect(firstTool["type"] as? String == "local_shell")
    }

    @Test("doGenerate decodes shell tool fixture")
    func doGenerateDecodesShellToolFixture() async throws {
        let capture = RequestCapture()
        let model = try makeModel(
            modelId: "gpt-5.1",
            fetch: makeJSONFetch(fixture: "openai-shell-tool.1", capture: capture)
        )

        let result = try await model.doGenerate(options: .init(
            prompt: samplePrompt,
            tools: [makePlainShellTool()]
        ))

        let toolCalls = result.content.compactMap { content -> LanguageModelV3ToolCall? in
            if case .toolCall(let call) = content { return call }
            return nil
        }
        let textParts = result.content.compactMap { content -> LanguageModelV3Text? in
            if case .text(let text) = content { return text }
            return nil
        }
        let toolResults = result.content.compactMap { content -> LanguageModelV3ToolResult? in
            if case .toolResult(let toolResult) = content { return toolResult }
            return nil
        }

        #expect(toolCalls.count == 1)
        #expect(toolResults.isEmpty)
        #expect(textParts.isEmpty)
        #expect(result.finishReason.unified == .stop)
        #expect(result.providerMetadata?["openai"]?["responseId"] == .string("resp_0f0d479976b1e9a600692f61be5948819783b655c7a54af2a2"))

        #expect(toolCalls[0].toolCallId == "call_udkLUvR8lWvG8cDO2B6GNpvZ")
        #expect(toolCalls[0].toolName == "shell")
        #expect(toolCalls[0].providerExecuted == nil)
        #expect(toolCalls[0].providerMetadata?["openai"]?["itemId"] == .string("sh_0f0d479976b1e9a600692f61bec0e08197a0864dc5ddf1d38c"))

        guard let toolInput = decodeToolInput(toolCalls[0].input),
              let action = toolInput["action"] as? [String: Any],
              let commands = action["commands"] as? [String] else {
            Issue.record("Expected shell tool action payload")
            return
        }

        #expect(commands.count == 3)
        #expect(commands[0] == "cd ~ && pwd")
        #expect(commands[1] == "cd ~/Desktop && pwd")
        #expect(commands[2].contains("THIS WORKS!"))
        #expect(action["timeout_ms"] == nil)

        guard let requestBody = decodeRequestBody(await capture.current()),
              let tools = requestBody["tools"] as? [[String: Any]],
              let firstTool = tools.first else {
            Issue.record("Missing request body for shell tool fixture")
            return
        }

        #expect(requestBody["model"] as? String == "gpt-5.1")
        #expect(firstTool["type"] as? String == "shell")
    }

    @Test("doGenerate decodes MCP tool fixture")
    func doGenerateDecodesMCPToolFixture() async throws {
        let capture = RequestCapture()
        let model = try makeModel(
            modelId: "gpt-5-mini",
            fetch: makeJSONFetch(fixture: "openai-mcp-tool.1", capture: capture)
        )

        let result = try await model.doGenerate(options: .init(
            prompt: samplePrompt,
            tools: [makeDefaultMCPTool()]
        ))

        let reasoningParts = result.content.compactMap { content -> LanguageModelV3Reasoning? in
            if case .reasoning(let reasoning) = content { return reasoning }
            return nil
        }
        let toolCalls = result.content.compactMap { content -> LanguageModelV3ToolCall? in
            if case .toolCall(let call) = content { return call }
            return nil
        }
        let toolResults = result.content.compactMap { content -> LanguageModelV3ToolResult? in
            if case .toolResult(let toolResult) = content { return toolResult }
            return nil
        }
        let textParts = result.content.compactMap { content -> LanguageModelV3Text? in
            if case .text(let text) = content { return text }
            return nil
        }

        #expect(reasoningParts.count == 2)
        #expect(toolCalls.count == 1)
        #expect(toolResults.count == 1)
        #expect(textParts.count == 1)
        #expect(result.finishReason.unified == .stop)
        #expect(result.response?.id == "resp_0a4801d792de11eb00690ccb85294c8197b71ddda28cf382e0")
        #expect(result.providerMetadata?["openai"]?["responseId"] == .string("resp_0a4801d792de11eb00690ccb85294c8197b71ddda28cf382e0"))

        #expect(toolCalls[0].toolCallId == "mcp_0a4801d792de11eb00690ccb8c3fac8197a4fd94f4528cd432")
        #expect(toolCalls[0].toolName == "mcp.web_search_exa")
        #expect(toolCalls[0].providerExecuted == true)
        #expect(toolCalls[0].dynamic == true)
        #expect(toolCalls[0].input.contains("NYC mayoral election results 2025 latest"))

        #expect(toolResults[0].toolCallId == toolCalls[0].toolCallId)
        #expect(toolResults[0].toolName == "mcp.web_search_exa")
        #expect(toolResults[0].providerMetadata?["openai"]?["itemId"] == .string("mcp_0a4801d792de11eb00690ccb8c3fac8197a4fd94f4528cd432"))
        if case .object(let payload) = toolResults[0].result {
            #expect(payload["type"] == .string("call"))
            #expect(payload["name"] == .string("web_search_exa"))
            #expect(payload["serverLabel"] == .string("dmcp"))
            if case .string(let output) = payload["output"] {
                #expect(output.contains("Zohran Mamdani"))
            } else {
                Issue.record("Expected MCP tool output payload")
            }
        } else {
            Issue.record("Expected MCP tool result object")
        }

        #expect(textParts[0].text.contains("Zohran Mamdani projected as the winner"))

        guard let requestBody = decodeRequestBody(await capture.current()),
              let tools = requestBody["tools"] as? [[String: Any]],
              let firstTool = tools.first else {
            Issue.record("Missing request body for MCP tool fixture")
            return
        }

        #expect(requestBody["model"] as? String == "gpt-5-mini")
        #expect(firstTool["type"] as? String == "mcp")
        #expect(firstTool["server_label"] as? String == "dmcp")
        #expect(firstTool["server_url"] as? String == "https://mcp.exa.ai/mcp")
        #expect(firstTool["server_description"] as? String == "A web-search API for AI agents")
        #expect(firstTool["require_approval"] as? String == "never")
    }

    @Test("doStream emits shell skill fixture events")
    func doStreamMatchesShellSkillsFixture() async throws {
        let model = try makeModel(
            modelId: "gpt-5.2",
            fetch: makeStreamFetch(fixture: "openai-shell-skills.1")
        )

        let result = try await model.doStream(options: .init(
            prompt: samplePrompt,
            tools: [makeShellTool()]
        ))
        let parts = try await collectStreamParts(result)

        let toolCalls = parts.compactMap { part -> LanguageModelV3ToolCall? in
            if case .toolCall(let call) = part { return call }
            return nil
        }
        let toolResults = parts.compactMap { part -> LanguageModelV3ToolResult? in
            if case .toolResult(let result) = part { return result }
            return nil
        }
        let responseMetadata = parts.compactMap { part -> (id: String?, modelId: String?, timestamp: Date?)? in
            if case .responseMetadata(let id, let modelId, let timestamp) = part {
                return (id: id, modelId: modelId, timestamp: timestamp)
            }
            return nil
        }
        let finishParts = parts.compactMap { part -> (finishReason: LanguageModelV3FinishReason, usage: LanguageModelV3Usage, providerMetadata: SharedV3ProviderMetadata?)? in
            if case .finish(let finishReason, let usage, let providerMetadata) = part {
                return (finishReason: finishReason, usage: usage, providerMetadata: providerMetadata)
            }
            return nil
        }

        #expect(responseMetadata.count == 1)
        #expect(responseMetadata.first?.id == "resp_049350089f7281c400698f717727d08191a446ae1621ed9503")
        #expect(toolCalls.count == 2)
        #expect(toolResults.count == 2)
        #expect(collectText(parts).contains("Build a STOP large signal"))

        #expect(toolCalls[0].toolCallId == "call_ckIythV1s1RcnbGV4F34THGN")
        #expect(toolCalls[0].providerExecuted == true)
        #expect(toolCalls[1].toolCallId == "call_Ud8yNtRknjWh2OA6COEutgOK")
        #expect(toolCalls[1].providerExecuted == true)

        #expect(finishParts.count == 1)
        #expect(finishParts[0].finishReason.unified == LanguageModelV3FinishReason.Unified.stop)
        #expect(finishParts[0].providerMetadata?["openai"]?["responseId"] == JSONValue.string("resp_049350089f7281c400698f717727d08191a446ae1621ed9503"))
    }

    @Test("doStream emits local shell fixture events")
    func doStreamEmitsLocalShellFixtureEvents() async throws {
        let capture = RequestCapture()
        let model = try makeModel(
            modelId: "gpt-5-codex",
            fetch: makeStreamFetch(fixture: "openai-local-shell-tool.1", capture: capture)
        )

        let result = try await model.doStream(options: .init(
            prompt: samplePrompt,
            tools: [makeLocalShellTool()]
        ))
        let parts = try await collectStreamParts(result)

        let reasoningStarts = parts.compactMap { part -> SharedV3ProviderMetadata? in
            if case .reasoningStart(_, let providerMetadata) = part { return providerMetadata }
            return nil
        }
        let reasoningEnds = parts.compactMap { part -> SharedV3ProviderMetadata? in
            if case .reasoningEnd(_, let providerMetadata) = part { return providerMetadata }
            return nil
        }
        let toolCalls = parts.compactMap { part -> LanguageModelV3ToolCall? in
            if case .toolCall(let call) = part { return call }
            return nil
        }
        let toolResults = parts.compactMap { part -> LanguageModelV3ToolResult? in
            if case .toolResult(let toolResult) = part { return toolResult }
            return nil
        }
        let responseMetadata = parts.compactMap { part -> (id: String?, modelId: String?, timestamp: Date?)? in
            if case .responseMetadata(let id, let modelId, let timestamp) = part {
                return (id: id, modelId: modelId, timestamp: timestamp)
            }
            return nil
        }
        let finishParts = parts.compactMap { part -> (finishReason: LanguageModelV3FinishReason, providerMetadata: SharedV3ProviderMetadata?)? in
            if case .finish(let finishReason, _, let providerMetadata) = part {
                return (finishReason: finishReason, providerMetadata: providerMetadata)
            }
            return nil
        }

        #expect(responseMetadata.count == 1)
        #expect(responseMetadata[0].id == "resp_68da7fd5d24481949fc2cf1cc60377050faf5df54b42d9a6")
        #expect(responseMetadata[0].modelId == "gpt-5-codex")
        #expect(reasoningStarts.count == 1)
        #expect(reasoningEnds.count == 1)
        #expect(reasoningStarts[0]["openai"]?["itemId"] == .string("rs_68da7fd65a3481948bbb35ff2c79c6c20faf5df54b42d9a6"))
        #expect(reasoningEnds[0]["openai"]?["itemId"] == .string("rs_68da7fd65a3481948bbb35ff2c79c6c20faf5df54b42d9a6"))
        #expect(toolCalls.count == 1)
        #expect(toolResults.isEmpty)

        #expect(toolCalls[0].toolCallId == "call_h3nm8hUG0KO9tVNuRACkL1ri")
        #expect(toolCalls[0].toolName == "shell")
        #expect(toolCalls[0].providerExecuted == nil)
        #expect(toolCalls[0].providerMetadata?["openai"]?["itemId"] == .string("lsh_68da7fd99b3c8194bd624b18c0c0851b0faf5df54b42d9a6"))

        guard let toolInput = decodeToolInput(toolCalls[0].input),
              let action = toolInput["action"] as? [String: Any],
              let command = action["command"] as? [String],
              let env = action["env"] as? [String: Any] else {
            Issue.record("Expected streamed local shell action payload")
            return
        }

        #expect(action["type"] as? String == "exec")
        #expect(command == ["ls", "-a", "~"])
        #expect(env.isEmpty)

        #expect(finishParts.count == 1)
        #expect(finishParts[0].finishReason.unified == .stop)
        #expect(finishParts[0].providerMetadata?["openai"]?["responseId"] == .string("resp_68da7fd5d24481949fc2cf1cc60377050faf5df54b42d9a6"))

        guard let requestBody = decodeRequestBody(await capture.current()),
              let tools = requestBody["tools"] as? [[String: Any]],
              let firstTool = tools.first else {
            Issue.record("Missing streamed request body for local shell fixture")
            return
        }

        #expect(requestBody["model"] as? String == "gpt-5-codex")
        #expect(firstTool["type"] as? String == "local_shell")
    }

    @Test("doStream emits shell tool fixture events")
    func doStreamEmitsShellToolFixtureEvents() async throws {
        let capture = RequestCapture()
        let model = try makeModel(
            modelId: "gpt-5.1",
            fetch: makeStreamFetch(fixture: "openai-shell-tool.1", capture: capture)
        )

        let result = try await model.doStream(options: .init(
            prompt: samplePrompt,
            tools: [makePlainShellTool()]
        ))
        let parts = try await collectStreamParts(result)

        let toolCalls = parts.compactMap { part -> LanguageModelV3ToolCall? in
            if case .toolCall(let call) = part { return call }
            return nil
        }
        let toolResults = parts.compactMap { part -> LanguageModelV3ToolResult? in
            if case .toolResult(let toolResult) = part { return toolResult }
            return nil
        }
        let responseMetadata = parts.compactMap { part -> (id: String?, modelId: String?)? in
            if case .responseMetadata(let id, let modelId, _) = part {
                return (id: id, modelId: modelId)
            }
            return nil
        }
        let finishParts = parts.compactMap { part -> (finishReason: LanguageModelV3FinishReason, providerMetadata: SharedV3ProviderMetadata?)? in
            if case .finish(let finishReason, _, let providerMetadata) = part {
                return (finishReason: finishReason, providerMetadata: providerMetadata)
            }
            return nil
        }

        #expect(responseMetadata.count == 2)
        #expect(responseMetadata[0].id == "resp_0434d6d64b12b08900692f639c40408195a50fd07b77ce08a7")
        #expect(responseMetadata[0].modelId == "gpt-5.1-2025-11-13")
        #expect(responseMetadata[1].id == "resp_0434d6d64b12b08900692f639d784481959af65f985b9c13e2")
        #expect(responseMetadata[1].modelId == "gpt-5.1-2025-11-13")
        #expect(toolCalls.count == 1)
        #expect(toolResults.isEmpty)
        #expect(collectText(parts).contains("Here are the files and folders in your `~/Desktop` directory"))
        #expect(collectText(parts).contains("dec1.txt"))

        #expect(toolCalls[0].toolCallId == "call_pbxjNs1tMJUahLZKAS9qLtvw")
        #expect(toolCalls[0].toolName == "shell")
        #expect(toolCalls[0].providerExecuted == nil)
        #expect(toolCalls[0].providerMetadata?["openai"]?["itemId"] == .string("sh_0434d6d64b12b08900692f639c9f0481959c30e03ca0bb2ef8"))

        guard let toolInput = decodeToolInput(toolCalls[0].input),
              let action = toolInput["action"] as? [String: Any],
              let commands = action["commands"] as? [String] else {
            Issue.record("Expected streamed shell tool action payload")
            return
        }

        #expect(commands == ["ls -a ~/Desktop"])
        #expect(action["timeout_ms"] == nil)

        #expect(finishParts.count == 1)
        #expect(finishParts[0].finishReason.unified == .stop)
        #expect(finishParts[0].providerMetadata?["openai"]?["responseId"] == .string("resp_0434d6d64b12b08900692f639d784481959af65f985b9c13e2"))

        guard let requestBody = decodeRequestBody(await capture.current()),
              let tools = requestBody["tools"] as? [[String: Any]],
              let firstTool = tools.first else {
            Issue.record("Missing streamed request body for shell tool fixture")
            return
        }

        #expect(requestBody["model"] as? String == "gpt-5.1")
        #expect(firstTool["type"] as? String == "shell")
    }

    @Test("doStream emits MCP tool fixture events")
    func doStreamEmitsMCPToolFixtureEvents() async throws {
        let capture = RequestCapture()
        let model = try makeModel(
            modelId: "gpt-5-mini",
            fetch: makeStreamFetch(fixture: "openai-mcp-tool.1", capture: capture)
        )

        let result = try await model.doStream(options: .init(
            prompt: samplePrompt,
            tools: [makeDefaultMCPTool()]
        ))
        let parts = try await collectStreamParts(result)

        let toolCalls = parts.compactMap { part -> LanguageModelV3ToolCall? in
            if case .toolCall(let call) = part { return call }
            return nil
        }
        let toolResults = parts.compactMap { part -> LanguageModelV3ToolResult? in
            if case .toolResult(let toolResult) = part { return toolResult }
            return nil
        }
        let reasoningStarts = parts.compactMap { part -> SharedV3ProviderMetadata? in
            if case .reasoningStart(_, let providerMetadata) = part { return providerMetadata }
            return nil
        }
        let responseMetadata = parts.compactMap { part -> (id: String?, modelId: String?)? in
            if case .responseMetadata(let id, let modelId, _) = part {
                return (id: id, modelId: modelId)
            }
            return nil
        }

        #expect(responseMetadata.count == 1)
        #expect(responseMetadata[0].id == "resp_0c72b1033351981300690ccf79c6d88193b7d054f4f83ad50a")
        #expect(responseMetadata[0].modelId == "gpt-5-mini-2025-08-07")
        #expect(reasoningStarts.count >= 2)
        #expect(toolCalls.count >= 2)
        #expect(toolResults.count >= 2)

        #expect(toolCalls[0].toolName == "mcp.web_search_exa")
        #expect(toolCalls[0].providerExecuted == true)
        #expect(toolCalls[0].dynamic == true)
        #expect(toolCalls[0].input.contains("2025 New York City mayoral election results Nov 2025 latest results"))
        #expect(toolCalls[1].input.contains("NYC Board of Elections 2025 mayoral results"))

        #expect(toolResults[0].toolCallId == toolCalls[0].toolCallId)
        if case .object(let payload) = toolResults[0].result {
            #expect(payload["type"] == .string("call"))
            #expect(payload["name"] == .string("web_search_exa"))
        } else {
            Issue.record("Expected streamed MCP tool result object")
        }

        #expect(collectText(parts).contains("Zohran Mamdani"))

        guard let requestBody = decodeRequestBody(await capture.current()),
              let tools = requestBody["tools"] as? [[String: Any]],
              let firstTool = tools.first else {
            Issue.record("Missing streamed request body for MCP tool fixture")
            return
        }

        #expect(firstTool["type"] as? String == "mcp")
        #expect(firstTool["server_label"] as? String == "dmcp")
        #expect(firstTool["require_approval"] as? String == "never")
    }

    @Test("doGenerate preserves phase metadata from fixture")
    func doGeneratePreservesPhaseMetadataFromFixture() async throws {
        let model = try makeModel(
            modelId: "gpt-5.3-codex",
            fetch: makeJSONFetch(fixture: "openai-phase.1")
        )

        let result = try await model.doGenerate(options: .init(
            prompt: samplePrompt
        ))

        let textParts = result.content.compactMap { content -> LanguageModelV3Text? in
            if case .text(let text) = content { return text }
            return nil
        }

        #expect(textParts.count == 2)
        #expect(textParts[0].providerMetadata?["openai"]?["itemId"] == .string("msg_0465b6d1ae1f97c500699f883243a481a3b50b985223592984"))
        #expect(textParts[0].providerMetadata?["openai"]?["phase"] == .string("commentary"))
        #expect(textParts[1].providerMetadata?["openai"]?["itemId"] == .string("msg_0465b6d1ae1f97c500699f8835e09c81a3b91e9d502ff18555"))
        #expect(textParts[1].providerMetadata?["openai"]?["phase"] == .string("final_answer"))
        #expect(textParts[0].text.contains("I’ll quickly check reliable"))
        #expect(textParts[1].text.contains("Wednesday, February 25, 2026"))
    }

    @Test("doStream preserves phase metadata from fixture")
    func doStreamPreservesPhaseMetadataFromFixture() async throws {
        let model = try makeModel(
            modelId: "gpt-5.3-codex",
            fetch: makeStreamFetch(fixture: "openai-phase.1")
        )

        let result = try await model.doStream(options: .init(
            prompt: samplePrompt
        ))
        let parts = try await collectStreamParts(result)

        let textStarts = parts.compactMap { part -> SharedV3ProviderMetadata? in
            if case .textStart(_, let providerMetadata) = part { return providerMetadata }
            return nil
        }
        let textEnds = parts.compactMap { part -> SharedV3ProviderMetadata? in
            if case .textEnd(_, let providerMetadata) = part { return providerMetadata }
            return nil
        }
        let responseMetadata = parts.compactMap { part -> (id: String?, modelId: String?)? in
            if case .responseMetadata(let id, let modelId, _) = part {
                return (id: id, modelId: modelId)
            }
            return nil
        }

        #expect(responseMetadata.count == 1)
        #expect(responseMetadata[0].id == "resp_0a63f40a2632b74300699f8818e5648196a8fa657ae8091421")
        #expect(responseMetadata[0].modelId == "gpt-5.3-codex")
        #expect(textStarts.count == 2)
        #expect(textEnds.count == 2)
        #expect(textStarts[0]["openai"]?["phase"] == .string("commentary"))
        #expect(textStarts[1]["openai"]?["phase"] == .string("final_answer"))
        #expect(textEnds[0]["openai"]?["phase"] == .string("commentary"))
        #expect(textEnds[1]["openai"]?["phase"] == .string("final_answer"))
        #expect(collectText(parts).contains("Got it"))
        #expect(collectText(parts).contains("Here are a few **AI"))
    }

    @Test("doGenerate decodes web search fixture")
    func doGenerateDecodesWebSearchFixture() async throws {
        let capture = RequestCapture()
        let model = try makeModel(
            modelId: "gpt-5-nano",
            fetch: makeJSONFetch(fixture: "openai-web-search-tool.1", capture: capture)
        )

        let result = try await model.doGenerate(options: .init(
            prompt: samplePrompt,
            tools: [makeWebSearchTool()]
        ))

        let toolCalls = result.content.compactMap { content -> LanguageModelV3ToolCall? in
            if case .toolCall(let call) = content { return call }
            return nil
        }
        let toolResults = result.content.compactMap { content -> LanguageModelV3ToolResult? in
            if case .toolResult(let toolResult) = content { return toolResult }
            return nil
        }
        let textParts = result.content.compactMap { content -> LanguageModelV3Text? in
            if case .text(let text) = content { return text }
            return nil
        }

        #expect(toolCalls.count == 3)
        #expect(toolResults.count == 3)
        #expect(textParts.count == 1)
        #expect(result.finishReason.unified == .stop)

        #expect(toolCalls.allSatisfy { $0.toolName == "webSearch" })
        #expect(toolCalls.allSatisfy { $0.providerExecuted == true })
        #expect(toolCalls[0].toolCallId == "ws_0953eda47ee1741200693330682c988195aaa470a8cc51dfe4")
        #expect(toolCalls[1].toolCallId == "ws_0953eda47ee17412006933306f501c8195b9d3dfba4c547834")
        #expect(toolCalls[2].toolCallId == "ws_0953eda47ee1741200693330740e248195a2c77632e480424b")

        if case .object(let searchPayload) = toolResults[0].result,
           case .object(let searchAction)? = searchPayload["action"] {
            #expect(searchAction["type"] == .string("search"))
            #expect(searchAction["query"] == .string("tech news today December 5 2025"))
            if case .array(let sources)? = searchPayload["sources"] {
                #expect(sources.count >= 10)
            } else {
                Issue.record("Expected web search sources array")
            }
        } else {
            Issue.record("Expected web search result payload")
        }

        if case .object(let openPagePayload) = toolResults[1].result,
           case .object(let action)? = openPagePayload["action"] {
            #expect(action["type"] == .string("openPage"))
            #expect(action["url"] == .string("https://www.theverge.com/podcast/838932/openai-chatgpt-code-red-vergecast"))
        } else {
            Issue.record("Expected open_page payload")
        }

        if case .object(let findInPagePayload) = toolResults[2].result,
           case .object(let action)? = findInPagePayload["action"] {
            #expect(action["type"] == .string("findInPage"))
            #expect(action["pattern"] == .string("Vercel"))
        } else {
            Issue.record("Expected find_in_page payload")
        }

        #expect(textParts[0].text.contains("Short answer first"))
        #expect(textParts[0].text.contains("Vercel-related funding"))

        guard let requestBody = decodeRequestBody(await capture.current()),
              let include = requestBody["include"] as? [String],
              let tools = requestBody["tools"] as? [[String: Any]],
              let firstTool = tools.first else {
            Issue.record("Missing request body for web search fixture")
            return
        }

        #expect(include.contains("web_search_call.action.sources"))
        #expect(firstTool["type"] as? String == "web_search")
    }

    @Test("doStream emits web search fixture events")
    func doStreamEmitsWebSearchFixtureEvents() async throws {
        let capture = RequestCapture()
        let model = try makeModel(
            modelId: "gpt-5-nano",
            fetch: makeStreamFetch(fixture: "openai-web-search-tool.1", capture: capture)
        )

        let result = try await model.doStream(options: .init(
            prompt: samplePrompt,
            tools: [makeWebSearchTool()]
        ))
        let parts = try await collectStreamParts(result)

        let toolCalls = parts.compactMap { part -> LanguageModelV3ToolCall? in
            if case .toolCall(let call) = part { return call }
            return nil
        }
        let toolResults = parts.compactMap { part -> LanguageModelV3ToolResult? in
            if case .toolResult(let toolResult) = part { return toolResult }
            return nil
        }
        let responseMetadata = parts.compactMap { part -> (id: String?, modelId: String?)? in
            if case .responseMetadata(let id, let modelId, _) = part {
                return (id: id, modelId: modelId)
            }
            return nil
        }

        #expect(responseMetadata.count == 1)
        #expect(responseMetadata[0].id == "resp_0cc96ac817fdc57e00693337060a408198b92bf1f99cf1b8ec")
        #expect(responseMetadata[0].modelId == "gpt-5-mini-2025-08-07")
        #expect(toolCalls.count >= 6)
        #expect(toolResults.count >= 6)
        #expect(toolCalls.allSatisfy { $0.toolName == "webSearch" })
        #expect(toolCalls.allSatisfy { $0.providerExecuted == true })
        #expect(toolResults[0].toolCallId == "ws_0cc96ac817fdc57e006933370e71cc81989ece73cbdfe67d25")

        if case .object(let searchPayload) = toolResults[0].result,
           case .object(let action)? = searchPayload["action"] {
            #expect(action["type"] == .string("search"))
            #expect(action["query"] == .string("tech news today December 5 2025"))
        } else {
            Issue.record("Expected streamed search payload")
        }

        let hasOpenPage = toolResults.contains { toolResult in
            guard case .object(let payload) = toolResult.result,
                  case .object(let action)? = payload["action"] else {
                return false
            }
            return action["type"] == .string("openPage")
        }
        let hasFindInPage = toolResults.contains { toolResult in
            guard case .object(let payload) = toolResult.result,
                  case .object(let action)? = payload["action"] else {
                return false
            }
            return action["type"] == .string("findInPage")
        }

        #expect(hasOpenPage)
        #expect(hasFindInPage)
        #expect(collectText(parts).contains("I checked today’s tech headlines"))
        #expect(collectText(parts).contains("keyword pattern"))

        guard let requestBody = decodeRequestBody(await capture.current()),
              let include = requestBody["include"] as? [String],
              let tools = requestBody["tools"] as? [[String: Any]],
              let firstTool = tools.first else {
            Issue.record("Missing streamed request body for web search fixture")
            return
        }

        #expect(include.contains("web_search_call.action.sources"))
        #expect(firstTool["type"] as? String == "web_search")
    }

    @Test("doGenerate decodes reasoning encrypted content fixture")
    func doGenerateDecodesReasoningEncryptedContentFixture() async throws {
        let capture = RequestCapture()
        let model = try makeModel(
            modelId: "gpt-5-mini",
            fetch: makeJSONFetch(fixture: "openai-reasoning-encrypted-content.1", capture: capture)
        )

        let result = try await model.doGenerate(options: .init(
            prompt: samplePrompt,
            tools: [makeCodeInterpreterTool()]
        ))

        let reasoningParts = result.content.compactMap { content -> LanguageModelV3Reasoning? in
            if case .reasoning(let reasoning) = content { return reasoning }
            return nil
        }
        let textParts = result.content.compactMap { content -> LanguageModelV3Text? in
            if case .text(let text) = content { return text }
            return nil
        }

        #expect(reasoningParts.count == 1)
        #expect(textParts.count == 1)
        #expect(result.finishReason.unified == .stop)
        #expect(result.response?.id == "resp_0f35ed53160b395301693cc957829881909359e7f80cdd20b5")

        #expect(reasoningParts[0].text.contains("Reporting final result"))
        #expect(reasoningParts[0].text.contains("Final result: 570"))
        #expect(reasoningParts[0].providerMetadata?["openai"]?["itemId"] == .string("rs_0f35ed53160b395301693cc95817ac8190b978637daea4987e"))
        if case .string(let encrypted)? = reasoningParts[0].providerMetadata?["openai"]?["reasoningEncryptedContent"] {
            #expect(!encrypted.isEmpty)
        } else {
            Issue.record("Expected reasoning encrypted content metadata")
        }

        #expect(textParts[0].text.contains("12 + 7 = 19"))
        #expect(textParts[0].text.contains("Final result: 570"))
        #expect(textParts[0].providerMetadata?["openai"]?["itemId"] == .string("msg_0f35ed53160b395301693cc95c1d288190997018450969162b"))

        guard let requestBody = decodeRequestBody(await capture.current()),
              let tools = requestBody["tools"] as? [[String: Any]],
              let firstTool = tools.first else {
            Issue.record("Missing request body for reasoning encrypted content fixture")
            return
        }

        #expect(requestBody["model"] as? String == "gpt-5-mini")
        #expect(firstTool["type"] as? String == "code_interpreter")
    }

    @Test("doStream emits reasoning encrypted content fixture events")
    func doStreamEmitsReasoningEncryptedContentFixtureEvents() async throws {
        let capture = RequestCapture()
        let model = try makeModel(
            modelId: "gpt-5.1-codex-max",
            fetch: makeStreamFetch(fixture: "openai-reasoning-encrypted-content.1", capture: capture)
        )

        let result = try await model.doStream(options: .init(
            prompt: samplePrompt,
            tools: [makeCalculatorTool()],
            providerOptions: [
                "openai": [
                    "reasoningEffort": .string("high"),
                    "maxCompletionTokens": .number(32_000),
                    "store": .bool(false),
                    "include": .array([.string("reasoning.encrypted_content")]),
                    "reasoningSummary": .string("auto"),
                    "forceReasoning": .bool(true)
                ]
            ]
        ))
        let parts = try await collectStreamParts(result)

        let reasoningStarts = parts.compactMap { part -> (String, SharedV3ProviderMetadata?)? in
            if case .reasoningStart(let id, let providerMetadata) = part {
                return (id, providerMetadata)
            }
            return nil
        }
        let reasoningEnds = parts.compactMap { part -> (String, SharedV3ProviderMetadata?)? in
            if case .reasoningEnd(let id, let providerMetadata) = part {
                return (id, providerMetadata)
            }
            return nil
        }
        let reasoningDeltas = parts.compactMap { part -> String? in
            if case .reasoningDelta(_, let delta, _) = part { return delta }
            return nil
        }
        let toolCalls = parts.compactMap { part -> LanguageModelV3ToolCall? in
            if case .toolCall(let call) = part { return call }
            return nil
        }
        let responseMetadata = parts.compactMap { part -> (id: String?, modelId: String?)? in
            if case .responseMetadata(let id, let modelId, _) = part {
                return (id: id, modelId: modelId)
            }
            return nil
        }
        let finishParts = parts.compactMap { part -> LanguageModelV3FinishReason? in
            if case .finish(let finishReason, _, _) = part { return finishReason }
            return nil
        }

        #expect(responseMetadata.count == 4)
        #expect(responseMetadata[0].id == "resp_01830d662ab3856501693c321345c88190b0de00f3b9975691")
        #expect(responseMetadata.last?.id == "resp_01830d662ab3856501693c3217ba4c8190a3ddf6c839d4f12a")
        #expect(reasoningStarts.count == 1)
        #expect(reasoningEnds.count == 1)
        #expect(reasoningStarts[0].0 == "rs_01830d662ab3856501693c321405c88190be3ab04d5782d5f9:0")
        #expect(reasoningEnds[0].0 == "rs_01830d662ab3856501693c321405c88190be3ab04d5782d5f9:0")
        if case .string(let encrypted)? = reasoningEnds[0].1?["openai"]?["reasoningEncryptedContent"] {
            #expect(!encrypted.isEmpty)
        } else {
            Issue.record("Expected streamed reasoning encrypted content metadata")
        }

        #expect(reasoningDeltas.joined().contains("Calculating step-by-step using calculator"))
        #expect(toolCalls.count == 3)
        #expect(toolCalls.allSatisfy { $0.toolName == "calculator" })
        #expect(toolCalls.contains { $0.toolCallId == "call_AB6AaRZ1FYZB2RwS6A5vbdqn" && $0.input == "{\"a\":12,\"b\":7,\"op\":\"add\"}" })
        #expect(toolCalls.contains { $0.toolCallId == "call_Q6pW65MUgW9vF59BmItYGos3" && $0.input == "{\"a\":19,\"b\":3,\"op\":\"multiply\"}" })
        #expect(toolCalls.contains { $0.toolCallId == "call_Zl5vIMnD7dVAjgU6FkhmiCZh" && $0.input == "{\"a\":57,\"b\":10,\"op\":\"multiply\"}" })
        #expect(collectText(parts).contains("The final result is **570**."))
        #expect(finishParts.count == 1)
        #expect(finishParts[0].unified == .toolCalls)

        guard let requestBody = decodeRequestBody(await capture.current()),
              let include = requestBody["include"] as? [String],
              let tools = requestBody["tools"] as? [[String: Any]],
              let firstTool = tools.first else {
            Issue.record("Missing streamed request body for reasoning encrypted fixture")
            return
        }

        #expect(requestBody["model"] as? String == "gpt-5.1-codex-max")
        #expect(include.contains("reasoning.encrypted_content"))
        #expect(firstTool["type"] as? String == "function")
        #expect(firstTool["name"] as? String == "calculator")
    }

    @Test("doGenerate decodes code interpreter fixture")
    func doGenerateDecodesCodeInterpreterFixture() async throws {
        let capture = RequestCapture()
        let model = try makeModel(
            modelId: "gpt-5-nano",
            fetch: makeJSONFetch(fixture: "openai-code-interpreter-tool.1", capture: capture)
        )

        let result = try await model.doGenerate(options: .init(
            prompt: samplePrompt,
            tools: [makeCodeInterpreterTool()]
        ))

        let reasoningParts = result.content.compactMap { content -> LanguageModelV3Reasoning? in
            if case .reasoning(let reasoning) = content { return reasoning }
            return nil
        }
        let toolCalls = result.content.compactMap { content -> LanguageModelV3ToolCall? in
            if case .toolCall(let call) = content { return call }
            return nil
        }
        let toolResults = result.content.compactMap { content -> LanguageModelV3ToolResult? in
            if case .toolResult(let toolResult) = content { return toolResult }
            return nil
        }
        let textParts = result.content.compactMap { content -> LanguageModelV3Text? in
            if case .text(let text) = content { return text }
            return nil
        }
        let sourceParts = result.content.compactMap { content -> LanguageModelV3Source? in
            if case .source(let source) = content { return source }
            return nil
        }

        #expect(reasoningParts.count == 4)
        #expect(toolCalls.count == 3)
        #expect(toolResults.count == 3)
        #expect(textParts.count == 1)
        #expect(sourceParts.count == 1)
        #expect(result.finishReason.unified == .stop)

        guard let firstCallInput = decodeToolInput(toolCalls[0].input),
              let firstCode = firstCallInput["code"] as? String,
              let secondCallInput = decodeToolInput(toolCalls[1].input),
              let secondCode = secondCallInput["code"] as? String,
              let thirdCallInput = decodeToolInput(toolCalls[2].input),
              let thirdCode = thirdCallInput["code"] as? String else {
            Issue.record("Expected decodable code interpreter call inputs")
            return
        }

        #expect(toolCalls.allSatisfy { $0.toolName == "codeExecution" })
        #expect(toolCalls.allSatisfy { $0.providerExecuted == true })
        #expect(toolCalls[0].input.contains("\"containerId\":\"cntr_6903bf2c0470819090b2b1e63e0b66800c139a5d654a42ec\""))
        #expect(firstCode.contains("import random"))
        #expect(secondCode.contains("filename = \"/mnt/data/two_dice_sums_10000.txt\""))
        #expect(secondCode.contains("filename, os.path.getsize(filename)"))
        #expect(thirdCode.contains("os.path.getsize(filename), filename"))

        if case .object(let firstResult) = toolResults[0].result,
           case .array(let outputs)? = firstResult["outputs"],
           case .object(let firstOutput) = outputs.first {
            #expect(firstOutput["type"] == .string("logs"))
            #expect(firstOutput["logs"] == .string("(10000, 70024)"))
        } else {
            Issue.record("Expected code interpreter logs payload")
        }

        if case .object(let secondResult) = toolResults[1].result,
           case .array(let outputs)? = secondResult["outputs"] {
            #expect(outputs.isEmpty)
        } else {
            Issue.record("Expected empty outputs for file write step")
        }

        #expect(textParts[0].text.contains("Total sum across all 10,000 rolls: 70024"))
        #expect(textParts[0].text.contains("Download the file"))

        guard case .document(_, let mediaType, let title, let filename, let providerMetadata) = sourceParts[0] else {
            Issue.record("Expected document source from code interpreter fixture")
            return
        }
        #expect(mediaType == "text/plain")
        #expect(title == "two_dice_sums_10000.txt")
        #expect(filename == "two_dice_sums_10000.txt")
        #expect(providerMetadata?["openai"]?["type"] == .string("container_file_citation"))
        #expect(providerMetadata?["openai"]?["fileId"] == .string("cfile_6903bf45e3288191af3d56e6d23c3a4d"))
        #expect(providerMetadata?["openai"]?["containerId"] == .string("cntr_6903bf2c0470819090b2b1e63e0b66800c139a5d654a42ec"))

        guard let requestBody = decodeRequestBody(await capture.current()),
              let include = requestBody["include"] as? [String],
              let tools = requestBody["tools"] as? [[String: Any]],
              let firstTool = tools.first,
              let container = firstTool["container"] as? [String: Any] else {
            Issue.record("Missing request body for code interpreter fixture")
            return
        }

        #expect(requestBody["model"] as? String == "gpt-5-nano")
        #expect(include.contains("code_interpreter_call.outputs"))
        #expect(firstTool["type"] as? String == "code_interpreter")
        #expect(container["type"] as? String == "auto")
    }

    @Test("doStream emits code interpreter fixture events")
    func doStreamEmitsCodeInterpreterFixtureEvents() async throws {
        let capture = RequestCapture()
        let model = try makeModel(
            modelId: "gpt-5-nano",
            fetch: makeStreamFetch(fixture: "openai-code-interpreter-tool.1", capture: capture)
        )

        let result = try await model.doStream(options: .init(
            prompt: samplePrompt,
            tools: [makeCodeInterpreterTool()]
        ))
        let parts = try await collectStreamParts(result)

        let toolCalls = parts.compactMap { part -> LanguageModelV3ToolCall? in
            if case .toolCall(let call) = part { return call }
            return nil
        }
        let toolResults = parts.compactMap { part -> LanguageModelV3ToolResult? in
            if case .toolResult(let toolResult) = part { return toolResult }
            return nil
        }
        let sourceParts = parts.compactMap { part -> LanguageModelV3Source? in
            if case .source(let source) = part { return source }
            return nil
        }
        let responseMetadata = parts.compactMap { part -> (id: String?, modelId: String?)? in
            if case .responseMetadata(let id, let modelId, _) = part {
                return (id: id, modelId: modelId)
            }
            return nil
        }
        let finishParts = parts.compactMap { part -> LanguageModelV3FinishReason? in
            if case .finish(let finishReason, _, _) = part { return finishReason }
            return nil
        }

        #expect(responseMetadata.count == 1)
        #expect(responseMetadata[0].id == "resp_68c2e6efa238819383d5f52a2c2a3baa02d3a5742c7ddae9")
        #expect(responseMetadata[0].modelId == "gpt-5-nano-2025-08-07")
        #expect(toolCalls.count == 3)
        #expect(toolResults.count == 3)
        #expect(sourceParts.count == 1)
        #expect(toolCalls.allSatisfy { $0.toolName == "codeExecution" })
        #expect(toolCalls.allSatisfy { $0.providerExecuted == true })
        #expect(toolCalls[0].input.contains("\"containerId\":\"cntr_68c2e6f380d881908a57a82d394434ff02f484f5344062e9\""))
        #expect(toolCalls[1].input.contains("roll2dice_sums_10000.csv"))
        #expect(toolCalls[2].input.contains("sums[:20]"))

        if case .object(let firstResult) = toolResults[0].result,
           case .array(let outputs)? = firstResult["outputs"],
           case .object(let firstOutput) = outputs.first {
            #expect(firstOutput["logs"] == .string("(2, 12, 69868, 6.9868)"))
        } else {
            Issue.record("Expected streamed code interpreter logs payload")
        }

        guard case .document(_, let mediaType, let title, let filename, let providerMetadata) = sourceParts[0] else {
            Issue.record("Expected streamed document source from code interpreter fixture")
            return
        }
        #expect(mediaType == "text/plain")
        #expect(title == "roll2dice_sums_10000.csv")
        #expect(filename == "roll2dice_sums_10000.csv")
        #expect(providerMetadata?["openai"]?["type"] == .string("container_file_citation"))
        #expect(providerMetadata?["openai"]?["fileId"] == .string("cfile_68c2e7084ab48191a67824aa1f4c90f1"))
        #expect(providerMetadata?["openai"]?["containerId"] == .string("cntr_68c2e6f380d881908a57a82d394434ff02f484f5344062e9"))

        #expect(collectText(parts).contains("Total sum of all 10,000 trials: 69,868"))
        #expect(collectText(parts).contains("roll2dice_sums_10000.csv"))
        #expect(finishParts.count == 1)
        #expect(finishParts[0].unified == .stop)

        guard let requestBody = decodeRequestBody(await capture.current()),
              let include = requestBody["include"] as? [String],
              let tools = requestBody["tools"] as? [[String: Any]],
              let firstTool = tools.first,
              let container = firstTool["container"] as? [String: Any] else {
            Issue.record("Missing streamed request body for code interpreter fixture")
            return
        }

        #expect(include.contains("code_interpreter_call.outputs"))
        #expect(firstTool["type"] as? String == "code_interpreter")
        #expect(container["type"] as? String == "auto")
    }

    @Test("doGenerate emits MCP approval request turn 1")
    func doGenerateEmitsMCPApprovalRequestTurn1() async throws {
        let capture = RequestCapture()
        let model = try makeModel(
            modelId: "gpt-5-mini",
            fetch: makeJSONFetch(fixture: "openai-mcp-tool-approval.1", capture: capture)
        )

        let result = try await model.doGenerate(options: .init(
            prompt: samplePrompt,
            tools: [makeMCPTool()]
        ))

        let toolCalls = result.content.compactMap { content -> LanguageModelV3ToolCall? in
            if case .toolCall(let call) = content { return call }
            return nil
        }
        let approvalRequests = result.content.compactMap { content -> LanguageModelV3ToolApprovalRequest? in
            if case .toolApprovalRequest(let request) = content { return request }
            return nil
        }

        #expect(toolCalls.count == 1)
        #expect(approvalRequests.count == 1)
        #expect(result.finishReason.unified == .stop)

        #expect(toolCalls[0].toolCallId == "generated-0")
        #expect(toolCalls[0].toolName == "mcp.create_short_url")
        #expect(toolCalls[0].providerExecuted == true)
        #expect(toolCalls[0].dynamic == true)
        #expect(toolCalls[0].input.contains("\"url\":\"https://ai-sdk.dev/\""))
        #expect(toolCalls[0].input.contains("\"description\":\"\""))

        #expect(approvalRequests[0].approvalId == "mcpr_04f6b17429cf2b02006949a6712b1081968b3c7a72dec695d8")
        #expect(approvalRequests[0].toolCallId == "generated-0")

        guard let requestBody = decodeRequestBody(await capture.current()),
              let input = requestBody["input"] as? [[String: Any]],
              let tools = requestBody["tools"] as? [[String: Any]],
              let firstTool = tools.first else {
            Issue.record("Missing request body for MCP turn 1")
            return
        }

        #expect(input.count == 1)
        #expect(input[0]["role"] as? String == "user")
        #expect(firstTool["type"] as? String == "mcp")
        #expect(firstTool["server_label"] as? String == "zip1")
        #expect(firstTool["server_url"] as? String == "https://zip1.io/mcp")
        #expect(firstTool["server_description"] as? String == "Link shortener")
        #expect(firstTool["require_approval"] as? String == "always")
    }

    @Test("doStream emits MCP approval request turn 1")
    func doStreamEmitsMCPApprovalRequestTurn1() async throws {
        let capture = RequestCapture()
        let model = try makeModel(
            modelId: "gpt-5-mini",
            fetch: makeStreamFetch(fixture: "openai-mcp-tool-approval.1", capture: capture)
        )

        let result = try await model.doStream(options: .init(
            prompt: samplePrompt,
            tools: [makeMCPTool()]
        ))
        let parts = try await collectStreamParts(result)

        let toolCalls = parts.compactMap { part -> LanguageModelV3ToolCall? in
            if case .toolCall(let call) = part { return call }
            return nil
        }
        let approvalRequests = parts.compactMap { part -> LanguageModelV3ToolApprovalRequest? in
            if case .toolApprovalRequest(let request) = part { return request }
            return nil
        }
        let responseMetadata = parts.compactMap { part -> (id: String?, modelId: String?)? in
            if case .responseMetadata(let id, let modelId, _) = part {
                return (id: id, modelId: modelId)
            }
            return nil
        }

        #expect(responseMetadata.count == 1)
        #expect(responseMetadata[0].id == "resp_04a97b4fce127879006949a837a3a48195b37f26ae73f550c0")
        #expect(responseMetadata[0].modelId == "gpt-5-mini-2025-08-07")
        #expect(toolCalls.count == 1)
        #expect(approvalRequests.count == 1)
        #expect(collectText(parts).isEmpty)

        #expect(toolCalls[0].toolCallId == "generated-0")
        #expect(toolCalls[0].toolName == "mcp.create_short_url")
        #expect(toolCalls[0].providerExecuted == true)
        #expect(toolCalls[0].dynamic == true)
        #expect(toolCalls[0].input.contains("\"description\":\"Shortened link for ai-sdk.dev\""))

        #expect(approvalRequests[0].approvalId == "mcpr_04a97b4fce127879006949a83ac9308195a7f7b69ea82e91fe")
        #expect(approvalRequests[0].toolCallId == "generated-0")

        guard let requestBody = decodeRequestBody(await capture.current()),
              let tools = requestBody["tools"] as? [[String: Any]],
              let firstTool = tools.first else {
            Issue.record("Missing streamed request body for MCP turn 1")
            return
        }

        #expect(firstTool["type"] as? String == "mcp")
        #expect(firstTool["server_label"] as? String == "zip1")
        #expect(firstTool["require_approval"] as? String == "always")
    }

    @Test("doGenerate handles MCP approval denial turn 2")
    func doGenerateMatchesMCPApprovalTurn2() async throws {
        let capture = RequestCapture()
        let model = try makeModel(
            modelId: "gpt-5-mini",
            fetch: makeJSONFetch(fixture: "openai-mcp-tool-approval.2", capture: capture)
        )

        let result = try await model.doGenerate(options: .init(
            prompt: makeMCPApprovalTurn2Prompt(),
            tools: [makeMCPTool()]
        ))

        let textParts = result.content.compactMap { content -> LanguageModelV3Text? in
            if case .text(let text) = content { return text }
            return nil
        }

        #expect(textParts.count == 1)
        #expect(textParts[0].text.contains("I couldn't create the short link"))
        #expect(result.content.allSatisfy { content in
            if case .toolCall = content { return false }
            if case .toolApprovalRequest = content { return false }
            return true
        })
        #expect(result.finishReason.unified == .stop)

        guard let requestBody = decodeRequestBody(await capture.current()),
              let input = requestBody["input"] as? [[String: Any]] else {
            Issue.record("Missing request body for MCP turn 2")
            return
        }

        #expect(input.count == 3)
        #expect(input[1]["type"] as? String == "item_reference")
        #expect(input[1]["id"] as? String == "mcpr_04f6b17429cf2b02006949a6712b1081968b3c7a72dec695d8")
        #expect(input[2]["type"] as? String == "mcp_approval_response")
        #expect(input[2]["approval_request_id"] as? String == "mcpr_04f6b17429cf2b02006949a6712b1081968b3c7a72dec695d8")
        #expect(input[2]["approve"] as? Bool == false)
    }

    @Test("doGenerate handles MCP approval retry turn 3")
    func doGenerateMatchesMCPApprovalTurn3() async throws {
        let model = try makeModel(
            modelId: "gpt-5-mini",
            fetch: makeJSONFetch(fixture: "openai-mcp-tool-approval.3")
        )

        let result = try await model.doGenerate(options: .init(
            prompt: makeMCPApprovalTurn3Prompt(),
            tools: [makeMCPTool()]
        ))

        let toolCalls = result.content.compactMap { content -> LanguageModelV3ToolCall? in
            if case .toolCall(let call) = content { return call }
            return nil
        }
        let approvalRequests = result.content.compactMap { content -> LanguageModelV3ToolApprovalRequest? in
            if case .toolApprovalRequest(let request) = content { return request }
            return nil
        }

        #expect(toolCalls.count == 1)
        #expect(approvalRequests.count == 1)
        #expect(toolCalls[0].toolCallId == "generated-0")
        #expect(toolCalls[0].toolName == "mcp.create_short_url")
        #expect(toolCalls[0].providerExecuted == true)
        #expect(toolCalls[0].dynamic == true)
        #expect(approvalRequests[0].approvalId == "mcpr_04f6b17429cf2b02006949a68bf5808196b6f2008a315c9aa4")
        #expect(approvalRequests[0].toolCallId == "generated-0")
        #expect(result.finishReason.unified == .stop)
    }

    @Test("doGenerate handles MCP approval success turn 4")
    func doGenerateMatchesMCPApprovalTurn4() async throws {
        let model = try makeModel(
            modelId: "gpt-5-mini",
            fetch: makeJSONFetch(fixture: "openai-mcp-tool-approval.4")
        )

        let result = try await model.doGenerate(options: .init(
            prompt: makeMCPApprovalTurn4Prompt(),
            tools: [makeMCPTool()]
        ))

        let toolCalls = result.content.compactMap { content -> LanguageModelV3ToolCall? in
            if case .toolCall(let call) = content { return call }
            return nil
        }
        let toolResults = result.content.compactMap { content -> LanguageModelV3ToolResult? in
            if case .toolResult(let result) = content { return result }
            return nil
        }
        let textParts = result.content.compactMap { content -> LanguageModelV3Text? in
            if case .text(let text) = content { return text }
            return nil
        }

        #expect(toolCalls.count == 1)
        #expect(toolResults.count == 1)
        #expect(textParts.count == 1)
        #expect(toolCalls[0].toolCallId == "mcp_04f6b17429cf2b02006949a6908fc4819686c02f71f7faecc6")
        #expect(toolResults[0].toolCallId == toolCalls[0].toolCallId)
        #expect(toolResults[0].providerMetadata?["openai"]?["itemId"] == .string("mcp_04f6b17429cf2b02006949a6908fc4819686c02f71f7faecc6"))
        #expect(textParts[0].text.contains("https://zip1.io/oMAchr"))
        #expect(result.finishReason.unified == .stop)
    }

    @Test("doStream emits MCP approval retry turn 3 events")
    func doStreamMatchesMCPApprovalTurn3() async throws {
        let model = try makeModel(
            modelId: "gpt-5-mini",
            fetch: makeStreamFetch(fixture: "openai-mcp-tool-approval.3")
        )

        let result = try await model.doStream(options: .init(
            prompt: makeMCPApprovalTurn3Prompt(),
            tools: [makeMCPTool()]
        ))
        let parts = try await collectStreamParts(result)

        let toolCalls = parts.compactMap { part -> LanguageModelV3ToolCall? in
            if case .toolCall(let call) = part { return call }
            return nil
        }
        let approvalRequests = parts.compactMap { part -> LanguageModelV3ToolApprovalRequest? in
            if case .toolApprovalRequest(let request) = part { return request }
            return nil
        }

        #expect(toolCalls.count == 1)
        #expect(approvalRequests.count == 1)
        #expect(toolCalls[0].toolCallId == "generated-0")
        #expect(toolCalls[0].toolName == "mcp.create_short_url")
        #expect(toolCalls[0].providerExecuted == true)
        #expect(toolCalls[0].dynamic == true)
        #expect(approvalRequests[0].approvalId == "mcpr_04a97b4fce127879006949a8672ac081959f95aa8ceedb7cd9")
        #expect(approvalRequests[0].toolCallId == "generated-0")
        #expect(collectText(parts).isEmpty)
    }

    @Test("doStream emits MCP approval denial turn 2 events")
    func doStreamMatchesMCPApprovalTurn2() async throws {
        let model = try makeModel(
            modelId: "gpt-5-mini",
            fetch: makeStreamFetch(fixture: "openai-mcp-tool-approval.2")
        )

        let result = try await model.doStream(options: .init(
            prompt: makeMCPApprovalTurn2Prompt(),
            tools: [makeMCPTool()]
        ))
        let parts = try await collectStreamParts(result)

        #expect(parts.allSatisfy { part in
            if case .toolCall = part { return false }
            if case .toolApprovalRequest = part { return false }
            return true
        })
        #expect(collectText(parts).contains("I wasn’t able to create the short link"))
    }

    @Test("doStream emits MCP approval success turn 4 events")
    func doStreamMatchesMCPApprovalTurn4() async throws {
        let model = try makeModel(
            modelId: "gpt-5-mini",
            fetch: makeStreamFetch(fixture: "openai-mcp-tool-approval.4")
        )

        let result = try await model.doStream(options: .init(
            prompt: makeMCPApprovalTurn4Prompt(),
            tools: [makeMCPTool()]
        ))
        let parts = try await collectStreamParts(result)

        let toolCalls = parts.compactMap { part -> LanguageModelV3ToolCall? in
            if case .toolCall(let call) = part { return call }
            return nil
        }
        let toolResults = parts.compactMap { part -> LanguageModelV3ToolResult? in
            if case .toolResult(let result) = part { return result }
            return nil
        }

        #expect(toolCalls.count == 1)
        #expect(toolResults.count == 1)
        #expect(toolCalls[0].toolCallId == "mcp_04a97b4fce127879006949a87c14248195ac23dfe0854c03d3")
        #expect(toolResults[0].toolCallId == toolCalls[0].toolCallId)
        #expect(collectText(parts).contains("https://zip1.io/UDKvlw"))
    }
}
