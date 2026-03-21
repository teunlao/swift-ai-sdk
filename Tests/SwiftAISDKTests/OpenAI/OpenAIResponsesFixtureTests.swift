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
