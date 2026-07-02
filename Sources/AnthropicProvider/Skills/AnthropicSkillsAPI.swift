import Foundation
import AISDKProvider
import AISDKProviderUtils

struct AnthropicSkillResponse: Codable, Sendable, Equatable {
    let id: String
    let displayTitle: String?
    let name: String?
    let description: String?
    let latestVersion: String?
    let source: String
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case displayTitle = "display_title"
        case name
        case description
        case latestVersion = "latest_version"
        case source
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct AnthropicSkillVersionResponse: Codable, Sendable, Equatable {
    let type: String
    let skillId: String
    let name: String?
    let description: String?

    enum CodingKeys: String, CodingKey {
        case type
        case skillId = "skill_id"
        case name
        case description
    }
}

let anthropicSkillResponseSchema = FlexibleSchema(
    Schema<AnthropicSkillResponse>.codable(
        AnthropicSkillResponse.self,
        jsonSchema: [
            "type": "object",
            "required": ["id", "source", "created_at", "updated_at"],
            "properties": [
                "id": ["type": "string"],
                "display_title": ["type": ["string", "null"]],
                "name": ["type": ["string", "null"]],
                "description": ["type": ["string", "null"]],
                "latest_version": ["type": ["string", "null"]],
                "source": ["type": "string"],
                "created_at": ["type": "string"],
                "updated_at": ["type": "string"]
            ]
        ]
    )
)

let anthropicSkillVersionResponseSchema = FlexibleSchema(
    Schema<AnthropicSkillVersionResponse>.codable(
        AnthropicSkillVersionResponse.self,
        jsonSchema: [
            "type": "object",
            "required": ["type", "skill_id"],
            "properties": [
                "type": ["type": "string"],
                "skill_id": ["type": "string"],
                "name": ["type": ["string", "null"]],
                "description": ["type": ["string", "null"]]
            ]
        ]
    )
)
