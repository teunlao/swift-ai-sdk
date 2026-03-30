import Testing
@testable import OpenAIProvider

@Suite("OpenAILanguageModelCapabilities")
struct OpenAILanguageModelCapabilitiesTests {
    @Test("isReasoningModel matches refreshed upstream allowlist")
    func isReasoningModel() {
        let cases: [(String, Bool)] = [
            ("gpt-4.1", false),
            ("gpt-4.1-2025-04-14", false),
            ("gpt-4.1-mini", false),
            ("gpt-4.1-mini-2025-04-14", false),
            ("gpt-4.1-nano", false),
            ("gpt-4.1-nano-2025-04-14", false),
            ("gpt-4o", false),
            ("gpt-4o-2024-05-13", false),
            ("gpt-4o-2024-08-06", false),
            ("gpt-4o-2024-11-20", false),
            ("gpt-4o-audio-preview", false),
            ("gpt-4o-audio-preview-2024-12-17", false),
            ("gpt-4o-search-preview", false),
            ("gpt-4o-search-preview-2025-03-11", false),
            ("gpt-4o-mini-search-preview", false),
            ("gpt-4o-mini-search-preview-2025-03-11", false),
            ("gpt-4o-mini", false),
            ("gpt-4o-mini-2024-07-18", false),
            ("gpt-3.5-turbo-0125", false),
            ("gpt-3.5-turbo", false),
            ("gpt-3.5-turbo-1106", false),
            ("gpt-5-chat-latest", false),
            ("o1", true),
            ("o1-2024-12-17", true),
            ("o3-mini", true),
            ("o3-mini-2025-01-31", true),
            ("o3", true),
            ("o3-2025-04-16", true),
            ("o4-mini", true),
            ("o4-mini-2025-04-16", true),
            ("codex-mini-latest", false),
            ("computer-use-preview", false),
            ("gpt-5", true),
            ("gpt-5-2025-08-07", true),
            ("gpt-5-codex", true),
            ("gpt-5-mini", true),
            ("gpt-5-mini-2025-08-07", true),
            ("gpt-5-nano", true),
            ("gpt-5-nano-2025-08-07", true),
            ("gpt-5-pro", true),
            ("gpt-5-pro-2025-10-06", true),
            ("gpt-5.4-mini", true),
            ("gpt-5.4-mini-2026-03-17", true),
            ("gpt-5.4-nano", true),
            ("gpt-5.4-nano-2026-03-17", true),
            ("new-unknown-model", false),
            ("ft:gpt-4o-2024-08-06:org:custom:abc123", false),
            ("custom-model", false)
        ]

        for (modelId, expected) in cases {
            #expect(
                getOpenAILanguageModelCapabilities(for: modelId).isReasoningModel == expected,
                "Model \(modelId) reasoning capability mismatch"
            )
        }
    }

    @Test("supportsPriorityProcessing matches refreshed upstream exclusions")
    func supportsPriorityProcessing() {
        let cases: [(String, Bool)] = [
            ("gpt-4.1", true),
            ("gpt-5", true),
            ("gpt-5-mini", true),
            ("gpt-5-nano", false),
            ("gpt-5-chat-latest", false),
            ("gpt-5.3-chat-latest", true),
            ("gpt-5.4-mini", true),
            ("gpt-5.4-nano", false),
            ("gpt-5.4-nano-2026-03-17", false),
            ("o3", true),
            ("o4-mini", true),
            ("custom-model", false)
        ]

        for (modelId, expected) in cases {
            #expect(
                getOpenAILanguageModelCapabilities(for: modelId).supportsPriorityProcessing == expected,
                "Model \(modelId) priority processing mismatch"
            )
        }
    }

    @Test("supportsNonReasoningParameters matches refreshed upstream")
    func supportsNonReasoningParameters() {
        let cases: [(String, Bool)] = [
            ("gpt-5.1", true),
            ("gpt-5.1-chat-latest", true),
            ("gpt-5.1-codex-mini", true),
            ("gpt-5.1-codex", true),
            ("gpt-5.2", true),
            ("gpt-5.2-pro", true),
            ("gpt-5.2-chat-latest", true),
            ("gpt-5.3-chat-latest", true),
            ("gpt-5.4", true),
            ("gpt-5.4-mini", true),
            ("gpt-5.4-nano", true),
            ("gpt-5.4-pro", true),
            ("gpt-5.4-2026-03-05", true),
            ("gpt-5.4-mini-2026-03-17", true),
            ("gpt-5.4-nano-2026-03-17", true),
            ("gpt-5", false),
            ("gpt-5-mini", false),
            ("gpt-5-nano", false),
            ("gpt-5-pro", false),
            ("gpt-5-chat-latest", false)
        ]

        for (modelId, expected) in cases {
            #expect(
                getOpenAILanguageModelCapabilities(for: modelId).supportsNonReasoningParameters == expected,
                "Model \(modelId) non-reasoning parameter support mismatch"
            )
        }
    }

    @Test("responses model lists match refreshed upstream additions and removals")
    func responsesModelListsMatchRefreshedUpstream() {
        let expectedReasoningIds = [
            "gpt-5.2-codex",
            "gpt-5.3-chat-latest",
            "gpt-5.3-codex",
            "gpt-5.4",
            "gpt-5.4-2026-03-05",
            "gpt-5.4-mini",
            "gpt-5.4-mini-2026-03-17",
            "gpt-5.4-nano",
            "gpt-5.4-nano-2026-03-17",
            "gpt-5.4-pro",
            "gpt-5.4-pro-2026-03-05"
        ]

        let removedReasoningIds = [
            "codex-mini-latest",
            "computer-use-preview"
        ]

        let removedModelIds = [
            "gpt-4o-audio-preview-2024-10-01",
            "gpt-4-turbo",
            "gpt-4-turbo-2024-04-09",
            "gpt-4-turbo-preview",
            "gpt-4-0125-preview",
            "gpt-4-1106-preview",
            "gpt-4",
            "gpt-4-0613",
            "gpt-4.5-preview",
            "gpt-4.5-preview-2025-02-27",
            "chatgpt-4o-latest"
        ]

        let reasoningIds = Set(openAIResponsesReasoningModelIds.map(\.rawValue))
        let modelIds = Set(openAIResponsesModelIds.map(\.rawValue))

        for modelId in expectedReasoningIds {
            #expect(reasoningIds.contains(modelId), "Missing reasoning model id \(modelId)")
            #expect(modelIds.contains(modelId), "Missing responses model id \(modelId)")
        }

        for modelId in removedReasoningIds {
            #expect(!reasoningIds.contains(modelId), "Unexpected legacy reasoning model id \(modelId)")
            #expect(!modelIds.contains(modelId), "Unexpected legacy responses model id \(modelId)")
        }

        for modelId in removedModelIds {
            #expect(!modelIds.contains(modelId), "Unexpected legacy responses model id \(modelId)")
        }
    }
}
