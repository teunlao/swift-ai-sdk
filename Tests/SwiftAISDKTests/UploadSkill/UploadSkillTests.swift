import Foundation
import Testing
@testable import SwiftAISDK
import AISDKProvider
import AISDKProviderUtils

private actor UploadSkillOptionsCapture {
    private var options: [SkillsV4UploadSkillCallOptions] = []

    func append(_ value: SkillsV4UploadSkillCallOptions) {
        options.append(value)
    }

    func first() -> SkillsV4UploadSkillCallOptions? {
        options.first
    }
}

private final class MockSkillsAPI: SkillsV4 {
    let specificationVersion = "v4"
    let provider = "mock.skills"

    private let capture: UploadSkillOptionsCapture
    private let result: SkillsV4UploadSkillResult

    init(capture: UploadSkillOptionsCapture, result: SkillsV4UploadSkillResult) {
        self.capture = capture
        self.result = result
    }

    func uploadSkill(options: SkillsV4UploadSkillCallOptions) async throws -> SkillsV4UploadSkillResult {
        await capture.append(options)
        return result
    }
}

private final class MockSkillsProvider: ProviderV3, SkillsProvider {
    private let skillsAPI: any SkillsV4

    init(skillsAPI: any SkillsV4) {
        self.skillsAPI = skillsAPI
    }

    func skills() -> any SkillsV4 {
        skillsAPI
    }

    func languageModel(modelId: String) throws -> any LanguageModelV3 {
        throw NoSuchModelError(modelId: modelId, modelType: .languageModel)
    }

    func textEmbeddingModel(modelId: String) throws -> any EmbeddingModelV3<String> {
        throw NoSuchModelError(modelId: modelId, modelType: .textEmbeddingModel)
    }

    func imageModel(modelId: String) throws -> any ImageModelV3 {
        throw NoSuchModelError(modelId: modelId, modelType: .imageModel)
    }
}

private final class UnsupportedSkillsProvider: ProviderV3 {
    func languageModel(modelId: String) throws -> any LanguageModelV3 {
        throw NoSuchModelError(modelId: modelId, modelType: .languageModel)
    }

    func textEmbeddingModel(modelId: String) throws -> any EmbeddingModelV3<String> {
        throw NoSuchModelError(modelId: modelId, modelType: .textEmbeddingModel)
    }

    func imageModel(modelId: String) throws -> any ImageModelV3 {
        throw NoSuchModelError(modelId: modelId, modelType: .imageModel)
    }
}

@Suite("uploadSkill")
struct UploadSkillTests {
    @Test("passes files, display title, and provider options through to the skills API")
    func passesFilesAndOptions() async throws {
        let capture = UploadSkillOptionsCapture()
        let api = MockSkillsAPI(
            capture: capture,
            result: .init(providerReference: ["anthropic": "skill-1"])
        )

        _ = try await uploadSkill(
            api: api,
            files: [
                SkillsV4File(path: "index.ts", content: .data(Data([0x01, 0x02, 0x03])))
            ],
            displayTitle: "My Skill",
            providerOptions: [
                "anthropic": [
                    "workspace": .string("test")
                ]
            ]
        )

        let first = await capture.first()
        #expect(first?.displayTitle == "My Skill")
        #expect(first?.providerOptions?["anthropic"]?["workspace"] == .string("test"))
        #expect(first?.files.count == 1)
        #expect(first?.files.first?.path == "index.ts")
        #expect(first?.files.first?.content == .data(Data([0x01, 0x02, 0x03])))
    }

    @Test("provider overload routes through skills capability")
    func providerOverloadUsesSkillsCapability() async throws {
        let capture = UploadSkillOptionsCapture()
        let api = MockSkillsAPI(
            capture: capture,
            result: .init(
                providerReference: ["anthropic": "skill-123"],
                displayTitle: "My Skill",
                name: "my-skill",
                latestVersion: "v1"
            )
        )
        let provider = MockSkillsProvider(skillsAPI: api)

        let result = try await uploadSkill(
            api: provider,
            files: [
                SkillsV4File(path: "index.ts", content: .base64("AQID"))
            ]
        )

        #expect(result.providerReference["anthropic"] == "skill-123")
        #expect(result.name == "my-skill")
        #expect(await capture.first()?.files.first?.content == .base64("AQID"))
    }

    @Test("rejects unsupported providers with upstream-style message")
    func rejectsUnsupportedProvider() async throws {
        do {
            _ = try await uploadSkill(
                api: UnsupportedSkillsProvider(),
                files: [
                    SkillsV4File(path: "index.ts", content: .data(Data([0x01])))
                ]
            )
            Issue.record("Expected unsupported provider to throw")
        } catch let error as InvalidArgumentError {
            #expect(error.message == "The provider does not support skills. Make sure it exposes a skills() method.")
        }
    }
}
