import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import CerebrasProvider

@Suite("Cerebras chat contracts")
struct CerebrasChatContractsTests {
    actor Capture {
        var request: URLRequest?
        func store(_ value: URLRequest) { request = value }
        func value() -> URLRequest? { request }
    }
    @Test(arguments: [true, false])
    func structuredFinalAnswerSuppressesRepeatedTools(structured: Bool) async throws {
        let capture = Capture()
        let response = Data(#"{"choices":[{"message":{"content":"{\"answer\":1}","tool_calls":[{"id":"call","function":{"name":"lookup","arguments":"{}"}}]},"finish_reason":"tool_calls"}]}"#.utf8)
        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(response), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
        }
        let prompt: LanguageModelV4Prompt = [.assistant(content: [.reasoning(.init(text: "Prior reasoning"))], providerOptions: nil)]
        let model = createCerebras(settings: .init(apiKey: "key", fetch: fetch))("glm")
        let result = try await model.doGenerate(options: .init(prompt: prompt, maxOutputTokens: 42,
                                                              responseFormat: structured ? .json(schema: ["type": "object"], name: nil, description: nil) : .text,
                                                              providerOptions: ["cerebras": ["parallelToolCalls": false, "reasoningFormat": "parsed"]]))
        let calls = result.content.compactMap { part -> LanguageModelV4ToolCall? in if case .toolCall(let call) = part { return call }; return nil }
        #expect(calls.count == (structured ? 0 : 1))
        #expect(result.finishReason.unified == (structured ? .stop : .toolCalls))
        #expect(result.finishReason.raw == "tool_calls")
        let request = try #require(await capture.value())
        let body = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
        guard case .object(let object) = body else { Issue.record("Expected JSON body"); return }
        #expect(object["max_completion_tokens"] == 42)
        #expect(object["parallel_tool_calls"] == false)
        #expect(object["reasoning_format"] == "parsed")
        #expect(object["messages"] == [["role": "assistant", "content": "", "reasoning": "Prior reasoning"]])
    }
    @Test func streamedStructuredAnswerDoesNotRequestToolExecution() async throws {
        let data = Data("data: {\"choices\":[{\"delta\":{\"content\":\"{\\\"answer\\\":1}\"}}]}\n\ndata: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"call\",\"function\":{\"name\":\"lookup\",\"arguments\":\"{}\"}}]},\"finish_reason\":\"tool_calls\"}]}\n\ndata: [DONE]\n\n".utf8)
        let fetch: FetchFunction = { request in FetchResponse(body: .data(data), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!) }
        let model = createCerebras(settings: .init(apiKey: "key", fetch: fetch))("glm")
        let stream = try await model.doStream(options: .init(prompt: [], responseFormat: .json(schema: nil, name: nil, description: nil))).stream
        var text = ""
        for try await part in stream {
            switch part {
            case .textDelta(_, let delta, _): text += delta
            case .toolInputStart, .toolInputDelta, .toolInputEnd, .toolCall: Issue.record("Final structured answer requested a tool")
            case .finish(let reason, _, _): #expect(reason == .init(unified: .stop, raw: "tool_calls"))
            case .error(let error): Issue.record("Unexpected error: \(error)")
            default: break
            }
        }
        #expect(text == #"{"answer":1}"#)
    }
    @Test func flatProviderErrorsRetainMessage() async throws {
        let fetch: FetchFunction = { request in
            FetchResponse(body: .data(Data(#"{"message":"Rejected","type":"invalid_request","param":"model","code":"bad_model"}"#.utf8)), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
        }
        do {
            _ = try await createCerebras(settings: .init(apiKey: "key", fetch: fetch))("glm").doGenerate(options: .init(prompt: []))
            Issue.record("Expected API error")
        } catch let error as APICallError { #expect(error.message == "Rejected") }
    }
}
