import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import OpenAIProvider

@Suite("Responses citation and opaque identity contracts")
struct OpenAIResponsesCitationsTests {
    private let annotations: [JSONValue] = [
        .object(["type": .string("url_citation"), "url": .string("https://cited.test"), "title": .string("Cited"), "start_index": .number(0.5), "end_index": .number(1e20)]),
        .object(["type": .string("file_citation"), "file_id": .string("cited_file"), "filename": .string("cited.txt"), "index": .number(2.5)]),
        .object(["type": .string("container_file_citation"), "file_id": .string("container_file"), "container_id": .string("container"), "filename": .string("container.txt"), "start_index": .number(1.5), "end_index": .number(3.5)]),
        .object(["type": .string("file_path"), "file_id": .string("/file/path"), "index": .number(-1)])
    ]
    private var message: JSONValue { .object([
        "type": .string("message"), "id": .string("message"), "role": .string("assistant"), "phase": .string("commentary"),
        "content": .array([.object(["type": .string("output_text"), "text": .string("answer"), "annotations": .array(annotations)])])
    ]) }
    private let web: JSONValue = .object([
        "type": .string("web_search_call"), "id": .string("web"), "status": .string("completed"), "action": .object([
            "type": .string("search"), "query": .string("query"), "sources": .array([
                .object(["type": .string("url"), "url": .string("https://retrieved.test")]),
                .object(["type": .string("url"), "url": .string("https://retrieved.test")])
            ])
        ])
    ])
    private var files: JSONValue { .object([
        "type": .string("file_search_call"), "id": .string("files"), "queries": .array([.string("query")]),
        "results": .array(["e\u{0301}", "é", "e\u{0301}"].enumerated().map { index, id in .object([
            "attributes": .object([:]), "file_id": .string(id), "filename": .string("file\(index).txt"), "score": .number(0.5), "text": .string("snippet")
        ]) })
    ]) }
    private func provider(_ payload: Data, streaming: Bool = false) throws -> OpenAIProvider {
        try createOpenAI(settings: .init(apiKey: "test", fetch: { request in
            FetchResponse(body: .data(payload), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": streaming ? "text/event-stream" : "application/json"])!)
        }))
    }
    private func sourceTag(_ source: LanguageModelV4Source) -> String {
        switch source {
        case .url: return "url"
        case .document(_, _, _, _, let metadata):
            if case .string(let type)? = metadata?["openai"]?["type"] { return type }; return "document"
        }
    }
    private func sourceId(_ source: LanguageModelV4Source) -> String {
        switch source { case .url(let id, _, _, _), .document(let id, _, _, _, _): return id }
    }
    private func verifyCitations(_ citations: [LanguageModelV4Citation]?) throws {
        let citations = try #require(citations)
        #expect(citations.count == 3)
        #expect(citations.map { sourceId($0.source) } == ["https://cited.test", "cited_file", "container_file"])
        let encoded = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(citations))
        guard case .array(let values) = encoded, values.count == 3, case .object(let url) = values[0], case .object(let file) = values[1], case .object(let container) = values[2] else {
            Issue.record("Missing encoded citations"); return
        }
        #expect(url["startIndex"] == .number(0.5) && url["endIndex"] == .number(1e20))
        #expect(file["startIndex"] == nil && file["endIndex"] == nil)
        #expect(container["startIndex"] == .number(1.5) && container["endIndex"] == .number(3.5))
        if case .document(_, let media, let title, let filename, let metadata) = citations[1].source {
            #expect(media == "text/plain" && title == "cited.txt" && filename == "cited.txt")
            #expect(metadata?["openai"] == ["type": .string("file_citation"), "fileId": .string("cited_file"), "index": .number(2.5)])
        } else { Issue.record("Missing document citation") }
        if case .url(_, let url, let title, _) = citations[0].source {
            #expect(url == "https://cited.test" && title == "Cited")
        } else { Issue.record("Missing URL citation") }
        if case .document(_, let media, let title, let filename, let metadata) = citations[2].source {
            #expect(media == "text/plain" && title == "container.txt" && filename == "container.txt")
            #expect(metadata?["openai"] == ["type": .string("container_file_citation"), "fileId": .string("container_file"), "containerId": .string("container")])
        } else { Issue.record("Missing container citation") }
    }

    @Test("Generated citations remain independent of retrieval sources and literal file-ID dedup", arguments: [false, true])
    func generatedCitations(retrieval: Bool) async throws {
        let payload = try JSONEncoder().encode(JSONValue.object(["output": .array([message] + (retrieval ? [web, files] : []))]))
        let result = try await provider(payload).responses("gpt-6").doGenerate(options: .init(prompt: []))
        let text = try #require(result.content.compactMap { if case .text(let value) = $0 { return value }; return nil }.first)
        #expect(text.providerMetadata?["openai"]?["annotations"] == .array(annotations))
        try verifyCitations(text.citations)
        let sources = result.content.compactMap { if case .source(let value) = $0 { return value }; return nil }
        #expect(sources.map(sourceTag) == (retrieval ? ["container_file_citation", "file_path", "url", "url", "file_search", "file_search"] : ["url", "file_citation", "container_file_citation", "file_path"]))
        #expect(Set(sources.map { Data(sourceId($0).utf8) }).count == sources.count)
        let path = try #require(sources.first { sourceTag($0) == "file_path" })
        if case .document(_, let media, let title, let filename, let metadata) = path {
            #expect(media == "application/octet-stream" && title == "/file/path" && filename == "/file/path")
            #expect(metadata?["openai"] == ["type": .string("file_path"), "fileId": .string("/file/path"), "index": .number(-1)])
        }
        if retrieval {
            let ids = sources.compactMap { source -> Data? in
                if case .document(_, _, _, _, let metadata) = source, metadata?["openai"]?["type"] == .string("file_search"),
                   case .string(let id)? = metadata?["openai"]?["fileId"] { return Data(id.utf8) }; return nil
            }
            #expect(ids == [Data("e\u{0301}".utf8), Data("é".utf8)])
        }
    }

    @Test("Stream source fallback waits for complete retrieval data and text IDs stay stable", arguments: [false, true])
    func streamedCitations(retrieval: Bool) async throws {
        var frames: [JSONValue] = [
            .object(["type": .string("response.output_item.added"), "output_index": .number(0.25), "item": .object(["type": .string("message"), "id": .string("message"), "phase": .string("commentary")])]),
            .object(["type": .string("response.output_text.delta"), "output_index": .number(0.25), "item_id": .string("rotated_delta"), "delta": .string("answer")])
        ]
        frames += annotations.map { .object(["type": .string("response.output_text.annotation.added"), "annotation": $0]) }
        if retrieval {
            frames += [
                .object(["type": .string("response.output_item.done"), "output_index": .number(1), "item": web]),
                .object(["type": .string("response.output_item.done"), "output_index": .number(1e20), "item": files])
            ]
        }
        frames += [
            .object(["type": .string("response.output_item.done"), "output_index": .number(0.25), "item": .object(["type": .string("message"), "id": .string("rotated_done")])]),
            .object(["type": .string("response.completed"), "response": .object([:])])
        ]
        let payload = Data(try frames.map { "data: \(String(decoding: try JSONEncoder().encode($0), as: UTF8.self))\n\n" }.joined().utf8)
        let response = try await provider(payload, streaming: true).responses("gpt-6").doStream(options: .init(prompt: [], includeRawChunks: true))
        var order: [String] = []
        var sources: [LanguageModelV4Source] = []
        var rawDoneId: String?
        for try await part in response.stream {
            switch part {
            case .textStart(let id, _), .textDelta(let id, _, _): #expect(id == "message")
            case .textEnd(let id, let metadata, let citations):
                #expect(id == "message")
                #expect(metadata?["openai"]?["itemId"] == .string("message"))
                #expect(metadata?["openai"]?["phase"] == .string("commentary"))
                #expect(metadata?["openai"]?["annotations"] == .array(annotations))
                try verifyCitations(citations); order.append("text-end")
            case .source(let source): sources.append(source); order.append(sourceTag(source))
            case .raw(let raw):
                if case .object(let object) = raw, object["type"] == .string("response.output_item.done"),
                   case .object(let item)? = object["item"], item["type"] == .string("message"), case .string(let id)? = item["id"] { rawDoneId = id }
            case .finish: order.append("finish")
            case .error: Issue.record("Unexpected citation stream error")
            default: break
            }
        }
        #expect(rawDoneId == "rotated_done")
        #expect(order == (retrieval ? ["container_file_citation", "file_path", "url", "url", "file_search", "file_search", "text-end", "finish"] : ["container_file_citation", "file_path", "text-end", "url", "file_citation", "finish"]))
        #expect(Set(sources.map { Data(sourceId($0).utf8) }).count == sources.count)
    }

    @Test("Generated approval IDs retain literal relationships in stream and prompt replay")
    func approvalIdentity() async throws {
        let ids = ["approval:e\u{0301}", "approval:é"]
        let calls: [JSONValue] = ids.enumerated().map { index, id in .object([
            "type": .string("mcp_call"), "id": .string("result_\(index)"), "approval_request_id": .string(id),
            "name": .string("read"), "arguments": .string("{}"), "server_label": .string("docs"), "status": .string("completed"), "output": .string("result")
        ]) }
        var frames: [JSONValue] = ids.enumerated().map { index, id in .object([
            "type": .string("response.output_item.done"), "output_index": .number(Double(index)), "item": .object([
                "type": .string("mcp_approval_request"), "id": .string(id), "name": .string("read"), "arguments": .string("{}"), "server_label": .string("docs")
            ])
        ]) }
        frames += calls.enumerated().map { index, item in .object(["type": .string("response.output_item.done"), "output_index": .number(Double(index + 2)), "item": item]) }
        frames.append(.object(["type": .string("response.completed"), "response": .object([:])]))
        let payload = Data(try frames.map { "data: \(String(decoding: try JSONEncoder().encode($0), as: UTF8.self))\n\n" }.joined().utf8)
        let response = try await provider(payload, streaming: true).responses("gpt-6").doStream(options: .init(prompt: []))
        var approvals: [LanguageModelV4ToolApprovalRequest] = []
        var results: [String] = []
        for try await part in response.stream {
            switch part {
            case .toolApprovalRequest(let request): approvals.append(request)
            case .toolResult(let result): results.append(result.toolCallId)
            case .error: Issue.record("Unexpected approval stream error")
            default: break
            }
        }
        #expect(approvals.map { Data($0.approvalId.utf8) } == ids.map { Data($0.utf8) })
        #expect(Set(approvals.map(\.toolCallId)).count == 2)
        #expect(results == approvals.map(\.toolCallId))
        let prompt: LanguageModelV4Prompt = [.assistant(content: approvals.map { approval in
            .toolCall(.init(toolCallId: approval.toolCallId, toolName: "mcp.read", input: .object([:]), providerExecuted: true,
                providerOptions: ["openai": ["approvalRequestId": .string(approval.approvalId)]]))
        }, providerOptions: nil)]
        let generated = try await provider(JSONEncoder().encode(JSONValue.object(["output": .array(calls)]))).responses("gpt-6").doGenerate(options: .init(prompt: prompt))
        let replayIds = generated.content.compactMap { if case .toolResult(let result) = $0 { return result.toolCallId }; return nil }
        #expect(replayIds == approvals.map(\.toolCallId))
    }

    @Test("Reasoning lifetimes preserve literal identities under rotated IDs and numeric output indices")
    func reasoningIdentity() async throws {
        let a = "r:e\u{0301}"
        let b = "r:é"
        let frames: [JSONValue] = [
            .object(["type": .string("response.output_item.added"), "output_index": .number(0.5), "item": .object(["type": .string("reasoning"), "id": .string(a), "encrypted_content": .string("a")])]),
            .object(["type": .string("response.output_item.added"), "output_index": .number(1e20), "item": .object(["type": .string("reasoning"), "id": .string(b), "encrypted_content": .string("b")])]),
            .object(["type": .string("response.reasoning_summary_part.done"), "output_index": .number(0.5), "item_id": .string("rotated_a"), "summary_index": .number(0)]),
            .object(["type": .string("response.reasoning_summary_part.added"), "output_index": .number(0.5), "item_id": .string("rotated_a"), "summary_index": .number(1.5)]),
            .object(["type": .string("response.reasoning_summary_text.delta"), "output_index": .number(0.5), "item_id": .string("rotated_a"), "summary_index": .number(1.5), "delta": .string("reason")]),
            .object(["type": .string("response.reasoning_summary_part.done"), "output_index": .number(0.5), "item_id": .string("rotated_a"), "summary_index": .number(1.5)]),
            .object(["type": .string("response.output_item.done"), "output_index": .number(0.5), "item": .object(["type": .string("reasoning"), "id": .string("rotated_a_done"), "encrypted_content": .string("final_a")])]),
            .object(["type": .string("response.output_item.done"), "output_index": .number(1e20), "item": .object(["type": .string("reasoning"), "id": .string("rotated_b_done"), "encrypted_content": .string("final_b")])]),
            .object(["type": .string("response.output_text.delta"), "output_index": .number(0.5), "item_id": .string("after_done"), "delta": .string("after")]),
            .object(["type": .string("response.completed"), "response": .object([:])])
        ]
        let payload = Data(try frames.map { "data: \(String(decoding: try JSONEncoder().encode($0), as: UTF8.self))\n\n" }.joined().utf8)
        let response = try await provider(payload, streaming: true).responses("gpt-6").doStream(options: .init(prompt: [], providerOptions: ["openai": ["store": .bool(false)]]))
        var starts: [Data] = []
        var ends: [Data] = []
        var encrypted: [JSONValue?] = []
        for try await part in response.stream {
            switch part {
            case .reasoningStart(let id, _): starts.append(Data(id.utf8))
            case .reasoningDelta(let id, _, let metadata):
                #expect(Data(id.utf8) == Data("\(a):1.5".utf8))
                #expect(metadata?["openai"]?["itemId"].map { if case .string(let id) = $0 { return Data(id.utf8) }; return Data() } == Data(a.utf8))
            case .reasoningEnd(let id, let metadata): ends.append(Data(id.utf8)); encrypted.append(metadata?["openai"]?["reasoningEncryptedContent"])
            case .textDelta(let id, _, _): #expect(id == "after_done")
            case .error: Issue.record("Unexpected reasoning error")
            default: break
            }
        }
        #expect(starts == [Data("\(a):0".utf8), Data("\(b):0".utf8), Data("\(a):1.5".utf8)])
        #expect(ends == [Data("\(a):0".utf8), Data("\(a):1.5".utf8), Data("\(b):0".utf8)])
        #expect(encrypted == [nil, .string("final_a"), .string("final_b")])
    }
}
