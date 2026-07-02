/**
 Skills specification version 4.

 Port of `@ai-sdk/provider/src/skills/v4/skills-v4.ts`.
 */
public protocol SkillsV4: Sendable {
    /// Skills interface version discriminator.
    var specificationVersion: String { get }

    /// Provider identifier.
    var provider: String { get }

    /// Uploads a new skill from the given files.
    func uploadSkill(options: SkillsV4UploadSkillCallOptions) async throws -> SkillsV4UploadSkillResult
}

/**
 Provider capability marker for providers that expose a v4 skills interface.
 */
public protocol SkillsProvider: Sendable {
    func skills() -> any SkillsV4
}
