import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Uploads a skill using a skills API interface.

 Port of `@ai-sdk/ai/src/upload-skill/upload-skill.ts`.
 */
public func uploadSkill(
    api: any SkillsV4,
    files: [SkillsV4File],
    displayTitle: String? = nil,
    providerOptions: ProviderOptions? = nil
) async throws -> DefaultUploadSkillResult {
    let result = try await api.uploadSkill(
        options: .init(
            files: files,
            displayTitle: displayTitle,
            providerOptions: providerOptions
        )
    )

    return DefaultUploadSkillResult(
        providerReference: result.providerReference,
        displayTitle: result.displayTitle,
        name: result.name,
        description: result.description,
        latestVersion: result.latestVersion,
        providerMetadata: result.providerMetadata,
        warnings: result.warnings
    )
}

public func uploadSkill(
    api: any ProviderV3,
    files: [SkillsV4File],
    displayTitle: String? = nil,
    providerOptions: ProviderOptions? = nil
) async throws -> DefaultUploadSkillResult {
    guard let skillsProvider = api as? any SkillsProvider else {
        throw InvalidArgumentError(
            argument: "api",
            message: "The provider does not support skills. Make sure it exposes a skills() method."
        )
    }

    return try await uploadSkill(
        api: skillsProvider.skills(),
        files: files,
        displayTitle: displayTitle,
        providerOptions: providerOptions
    )
}
