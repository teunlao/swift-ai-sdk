import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import OpenAIProvider
import SwiftAISDK

private actor CallerRequestCapture {
    private var value: JSONObject?

    func store(_ data: Data?) throws -> JSONObject {
        let body = try JSONDecoder().decode(JSONObject.self, from: data ?? Data())
        value = body
        return body
    }

    func body() -> JSONObject? { value }
}

private func callerModel(_ capture: CallerRequestCapture) throws -> OpenAIResponsesLanguageModel {
    let provider = try createOpenAI(settings: .init(apiKey: "test-key", fetch: { request in
        let body = try await capture.store(request.httpBody)
        let streaming = body["stream"] == .bool(true)
        let payload: Data
        if streaming {
            let events: [JSONValue] = [
                .object(["type": .string("response.created"), "response": .object([
                    "id": .string("resp_caller"), "model": .string("gpt-4.1"), "created_at": .number(1_700_000_000)
                ])]),
                .object(["type": .string("response.output_item.added"), "output_index": .number(0), "item": .object([
                    "type": .string("message"), "id": .string("msg_caller"), "status": .string("in_progress"),
                    "role": .string("assistant"), "content": .array([])
                ])]),
                .object(["type": .string("response.output_text.delta"), "item_id": .string("msg_caller"),
                         "output_index": .number(0), "delta": .string("ready"), "sequence_number": .number(2)]),
                .object(["type": .string("response.output_item.done"), "output_index": .number(0), "item": .object([
                    "type": .string("message"), "id": .string("msg_caller"), "status": .string("completed"),
                    "role": .string("assistant"), "content": .array([.object([
                        "type": .string("output_text"), "text": .string("ready"), "annotations": .array([])
                    ])])
                ])]),
                .object(["type": .string("response.completed"), "response": .object([:])])
            ]
            var data = Data()
            for event in events {
                data.append(Data("data: ".utf8))
                data.append(try JSONEncoder().encode(event))
                data.append(Data("\n\n".utf8))
            }
            data.append(Data("data: [DONE]\n\n".utf8))
            payload = data
        } else {
            payload = Data(#"{"id":"resp_caller","created_at":1700000000,"model":"gpt-4.1","output":[{"id":"msg_caller","type":"message","role":"assistant","status":"completed","content":[{"type":"output_text","text":"ready","annotations":[]}]}]}"#.utf8)
        }
        return FetchResponse(body: .data(payload), urlResponse: HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: nil,
            headerFields: ["content-type": streaming ? "text/event-stream" : "application/json"]
        )!)
    }))
    return provider.responses("gpt-4.1")
}

private func callerTool(_ suffix: String, addCaller: Bool = false) -> Tool {
    Tool(inputSchema: FlexibleSchema(jsonSchema(.object(["type": .string("object")]))))
        .withProviderToolCaller(ProviderToolCaller(prepareProviderOptions: { options in
            var result = options ?? [:]
            var openai: JSONObject = [:]
            if case .object(let existing)? = result["openai"] { openai = existing }
            var namespace: JSONObject = [:]
            if case .object(let existing)? = openai["namespace"] { namespace = existing }
            let name: String
            if case .string(let value)? = namespace["name"] { name = value } else { name = "" }
            namespace["name"] = .string(name + suffix)
            openai["namespace"] = .object(namespace)
            if addCaller {
                var callers: [JSONValue] = []
                if case .array(let existing)? = openai["allowedCallers"] { callers = existing }
                openai["allowedCallers"] = .array(callers + [.string("programmatic")])
            }
            result["openai"] = .object(openai)
            return result
        }))
}

@Suite("Provider tool-caller composition")
struct ProviderToolCallerTests {
    @Test(arguments: [false, true])
    func providerOptionsComposeForModelTools(streaming: Bool) async throws {
        let capture = CallerRequestCapture()
        let model = try callerModel(capture)
        let schema = FlexibleSchema(jsonSchema(.object(["type": .string("object")])))
        let tools: ToolSet = [
            "target": Tool(providerOptions: ["openai": .object([
                "namespace": .object(["name": .string("base"), "description": .string("Grouped functions")]),
                "allowedCallers": .array([.string("direct")]), "async": .bool(false)
            ])], inputSchema: schema),
            "hidden": Tool(inputSchema: schema),
            "first": callerTool("_first", addCaller: true),
            "second": callerTool("_second")
        ]
        let callers: ToolCallers = ["target": ["first", "AI_SDK_DIRECT_TOOL_CALL", "second"], "hidden": []]
        if streaming {
            let result = try streamText(model: model, tools: tools, experimentalToolCallers: callers, prompt: "run")
            #expect(try await result.text == "ready")
        } else {
            let result = try await generateText(model: model, tools: tools, experimentalToolCallers: callers, prompt: "run")
            #expect(result.text == "ready")
        }
        let body = try #require(await capture.body())
        guard case .array(let wireTools)? = body["tools"] else { Issue.record("Missing wire tools"); return }
        let objects = wireTools.compactMap { value -> JSONObject? in
            if case .object(let object) = value { return object }; return nil
        }
        let namespace = try #require(objects.first { $0["type"] == .string("namespace") })
        #expect(namespace["name"] == .string("base_first_second"))
        guard case .array(let functions)? = namespace["tools"] else { Issue.record("Missing namespace tools"); return }
        let target = try #require(functions.compactMap { value -> JSONObject? in
            if case .object(let object) = value { return object }; return nil
        }.first { $0["name"] == .string("target") })
        #expect(target["allowed_callers"] == .array([.string("direct"), .string("programmatic")]))
        #expect(target["async"] == .bool(false))
        #expect(!objects.contains { $0["name"] == .string("hidden") })
    }

    @Test
    func hostedProgramFactoryPreparesFunctionOptions() async throws {
        let capture = CallerRequestCapture()
        let model = try callerModel(capture)
        let schema = FlexibleSchema(jsonSchema(.object(["type": .string("object")])))
        let result = try await generateText(model: model, tools: [
            "program": openaiTools.programmaticToolCalling(),
            "target": Tool(providerOptions: ["openai": .object([
                "allowedCallers": .array([.string("direct")])
            ])], inputSchema: schema)
        ], experimentalToolCallers: ["target": ["program", "program"]], prompt: "run")
        #expect(result.text == "ready")
        let body = try #require(await capture.body())
        guard case .array(let wireTools)? = body["tools"] else { Issue.record("Missing wire tools"); return }
        let objects = wireTools.compactMap { value -> JSONObject? in
            if case .object(let object) = value { return object }; return nil
        }
        #expect(objects.contains { $0["type"] == .string("programmatic_tool_calling") })
        let target = try #require(objects.first { $0["name"] == .string("target") })
        #expect(target["allowed_callers"] == .array([.string("direct"), .string("programmatic")]))
    }

    @Test(arguments: [
        ["missing": ["caller"]],
        ["target": ["missing"]],
        ["target": ["plain"]],
        ["\u{212A}": ["caller"]],
        ["target": ["AI_SD\u{212A}_DIRECT_TOOL_CALL"]]
    ])
    func invalidCallerConfigurationIsRejected(_ callers: ToolCallers) async throws {
        let capture = CallerRequestCapture()
        let model = try callerModel(capture)
        let schema = FlexibleSchema(jsonSchema(.object(["type": .string("object")])))
        await #expect(throws: AISDKProvider.InvalidArgumentError.self) {
            _ = try await generateText(model: model, tools: [
                "target": Tool(inputSchema: schema), "plain": Tool(inputSchema: schema),
                "K": Tool(inputSchema: schema), "caller": callerTool("_caller")
            ], experimentalToolCallers: callers, prompt: "run")
        }
    }
}
