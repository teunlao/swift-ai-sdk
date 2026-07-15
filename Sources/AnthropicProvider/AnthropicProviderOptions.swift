import Foundation
import AISDKProvider
import AISDKProviderUtils

/// Known Anthropic Claude model identifiers for autocomplete.
/// See: https://docs.claude.com/en/docs/about-claude/models/overview
///
/// Port of `@ai-sdk/anthropic/src/anthropic-messages-options.ts`.
public let anthropicMessagesModelIds: [AnthropicMessagesModelId] = [
    "claude-3-5-haiku-20241022",
    "claude-3-5-haiku-latest",
    "claude-3-7-sonnet-20250219",
    "claude-3-7-sonnet-latest",
    "claude-3-haiku-20240307",
    "claude-haiku-4-5-20251001",
    "claude-haiku-4-5",
    "claude-opus-4-0",
    "claude-opus-4-1-20250805",
    "claude-opus-4-1",
    "claude-opus-4-20250514",
    "claude-opus-4-5",
    "claude-opus-4-5-20251101",
    "claude-sonnet-4-0",
    "claude-sonnet-4-20250514",
    "claude-sonnet-4-5-20250929",
    "claude-sonnet-4-5",
    "claude-sonnet-4-6",
    "claude-opus-4-6",
    "claude-opus-4-7",
    "claude-opus-4-8",
    "claude-fable-5",
    "claude-sonnet-5"
].map(AnthropicMessagesModelId.init(rawValue:))

public struct AnthropicThinkingOptions: Sendable, Equatable {
    public enum Mode: String, Sendable, Equatable {
        case enabled
        case disabled
        /// Adaptive thinking lets Claude dynamically determine when and how much
        /// to use extended thinking based on the complexity of each request.
        /// Supported on claude-opus-4-6 and claude-sonnet-4-6 and later.
        case adaptive
    }

    /// Controls how thinking content is returned in API responses.
    /// - `summarized`: thinking blocks contain summarized text. Default on
    ///   Claude Opus 4.6, Sonnet 4.6, and earlier Claude 4 models.
    /// - `omitted`: thinking blocks are returned with an empty `thinking` field.
    ///   The `signature` is still populated for multi-turn continuity. Default
    ///   on Claude Opus 4.7 and Claude Mythos Preview.
    public enum Display: String, Sendable, Equatable {
        case summarized
        case omitted
    }

    public var type: Mode
    public var budgetTokens: Int?
    public var display: Display?

    public init(type: Mode, budgetTokens: Int? = nil, display: Display? = nil) {
        self.type = type
        self.budgetTokens = budgetTokens
        self.display = display
    }
}

public enum AnthropicStructuredOutputMode: String, Sendable, Equatable {
    case outputFormat
    case jsonTool
    case auto
}

public enum AnthropicEffort: String, Sendable, Equatable {
    case low
    case medium
    case high
    case xhigh
    /// Maximum supported effort. Available on current frontier Claude models,
    /// including Fable 5, Opus 4.8, and Sonnet 5.
    case max
}

public enum AnthropicSpeed: String, Sendable, Equatable {
    case fast
    case standard
}

public enum AnthropicInferenceGeo: String, Sendable, Equatable {
    case us
    case global
}

public struct AnthropicMetadataOptions: Sendable, Equatable {
    public var userId: String?

    public init(userId: String? = nil) {
        self.userId = userId
    }
}

public struct AnthropicTaskBudget: Sendable, Equatable {
    public enum BudgetType: String, Sendable, Equatable {
        case tokens
    }

    public var type: BudgetType
    public var total: Int
    public var remaining: Int?

    public init(type: BudgetType = .tokens, total: Int, remaining: Int? = nil) {
        self.type = type
        self.total = total
        self.remaining = remaining
    }
}

public struct AnthropicFallback: Sendable, Equatable {
    public var model: String
    public var maxTokens: Int?
    public var thinking: [String: JSONValue]?
    public var outputConfig: [String: JSONValue]?
    public var speed: AnthropicSpeed?

    public init(
        model: String,
        maxTokens: Int? = nil,
        thinking: [String: JSONValue]? = nil,
        outputConfig: [String: JSONValue]? = nil,
        speed: AnthropicSpeed? = nil
    ) {
        self.model = model
        self.maxTokens = maxTokens
        self.thinking = thinking
        self.outputConfig = outputConfig
        self.speed = speed
    }
}

public struct AnthropicMCPServer: Sendable, Equatable {
    public enum ServerType: String, Sendable, Equatable {
        case url
    }

    public struct ToolConfiguration: Sendable, Equatable {
        public var enabled: Bool?
        public var allowedTools: [String]?

        public init(enabled: Bool? = nil, allowedTools: [String]? = nil) {
            self.enabled = enabled
            self.allowedTools = allowedTools
        }
    }

    public var type: ServerType
    public var name: String
    public var url: String
    public var authorizationToken: String?
    public var toolConfiguration: ToolConfiguration?

    public init(
        type: ServerType,
        name: String,
        url: String,
        authorizationToken: String? = nil,
        toolConfiguration: ToolConfiguration? = nil
    ) {
        self.type = type
        self.name = name
        self.url = url
        self.authorizationToken = authorizationToken
        self.toolConfiguration = toolConfiguration
    }
}

public struct AnthropicContainerOptions: Sendable, Equatable {
    public struct Skill: Sendable, Equatable {
        public enum SkillType: String, Sendable, Equatable {
            case anthropic
            case custom
        }

        public var type: SkillType
        public var skillId: String
        public var version: String?

        public init(type: SkillType, skillId: String, version: String? = nil) {
            self.type = type
            self.skillId = skillId
            self.version = version
        }
    }

    public var id: String?
    public var skills: [Skill]?

    public init(id: String? = nil, skills: [Skill]? = nil) {
        self.id = id
        self.skills = skills
    }
}

public struct AnthropicContextManagement: Sendable, Equatable {
    public enum Edit: Sendable, Equatable {
        case clearToolUses20250919(ClearToolUses20250919)
        case clearThinking20251015(ClearThinking20251015)
        case compact20260112(Compact20260112)

        public var type: String {
            switch self {
            case .clearToolUses20250919:
                return "clear_tool_uses_20250919"
            case .clearThinking20251015:
                return "clear_thinking_20251015"
            case .compact20260112:
                return "compact_20260112"
            }
        }
    }

    public struct ClearToolUses20250919: Sendable, Equatable {
        public struct Trigger: Sendable, Equatable {
            public enum TriggerType: String, Sendable, Equatable {
                case inputTokens = "input_tokens"
                case toolUses = "tool_uses"
            }

            public var type: TriggerType
            public var value: Double

            public init(type: TriggerType, value: Double) {
                self.type = type
                self.value = value
            }
        }

        public struct Keep: Sendable, Equatable {
            public let type: String = "tool_uses"
            public var value: Double

            public init(value: Double) {
                self.value = value
            }
        }

        public struct ClearAtLeast: Sendable, Equatable {
            public let type: String = "input_tokens"
            public var value: Double

            public init(value: Double) {
                self.value = value
            }
        }

        public var trigger: Trigger?
        public var keep: Keep?
        public var clearAtLeast: ClearAtLeast?
        public var clearToolInputs: Bool?
        public var excludeTools: [String]?

        public init(
            trigger: Trigger? = nil,
            keep: Keep? = nil,
            clearAtLeast: ClearAtLeast? = nil,
            clearToolInputs: Bool? = nil,
            excludeTools: [String]? = nil
        ) {
            self.trigger = trigger
            self.keep = keep
            self.clearAtLeast = clearAtLeast
            self.clearToolInputs = clearToolInputs
            self.excludeTools = excludeTools
        }
    }

    public struct ClearThinking20251015: Sendable, Equatable {
        public enum Keep: Sendable, Equatable {
            case all
            case thinkingTurns(Double)
        }

        public var keep: Keep?

        public init(keep: Keep? = nil) {
            self.keep = keep
        }
    }

    public struct Compact20260112: Sendable, Equatable {
        public struct Trigger: Sendable, Equatable {
            public var type: String = "input_tokens"
            public var value: Double

            public init(value: Double) {
                self.value = value
            }
        }

        public var trigger: Trigger?
        public var pauseAfterCompaction: Bool?
        public var instructions: String?

        public init(
            trigger: Trigger? = nil,
            pauseAfterCompaction: Bool? = nil,
            instructions: String? = nil
        ) {
            self.trigger = trigger
            self.pauseAfterCompaction = pauseAfterCompaction
            self.instructions = instructions
        }
    }

    public var edits: [Edit]

    public init(edits: [Edit]) {
        self.edits = edits
    }
}

public struct AnthropicCacheControl: Sendable, Equatable {
    public enum TTL: String, Sendable, Equatable {
        case fiveMinutes = "5m"
        case oneHour = "1h"
    }

    public var type: String?
    public var ttl: TTL?
    public var additionalFields: [String: JSONValue]

    public init(
        type: String? = "ephemeral",
        ttl: TTL? = nil,
        additionalFields: [String: JSONValue] = [:]
    ) {
        self.type = type
        self.ttl = ttl
        self.additionalFields = additionalFields
    }
}

public struct AnthropicProviderOptions: Sendable, Equatable {
    public var sendReasoning: Bool?
    public var structuredOutputMode: AnthropicStructuredOutputMode?
    public var thinking: AnthropicThinkingOptions?
    public var disableParallelToolUse: Bool?
    public var cacheControl: AnthropicCacheControl?
    public var metadata: AnthropicMetadataOptions?
    public var mcpServers: [AnthropicMCPServer]?
    public var container: AnthropicContainerOptions?
    public var toolStreaming: Bool?
    public var effort: AnthropicEffort?
    public var taskBudget: AnthropicTaskBudget?
    /// Enable fast mode for faster inference. Only supported on claude-opus-4-6.
    public var speed: AnthropicSpeed?
    public var inferenceGeo: AnthropicInferenceGeo?
    public var fallbacks: [AnthropicFallback]?
    public var contextManagement: AnthropicContextManagement?
    /// Extra `anthropic-beta` values to merge into the request header.
    /// Use for betas the SDK doesn't auto-detect (e.g.
    /// `["extended-cache-ttl-2025-04-11"]`).
    public var anthropicBeta: [String]?

    public init(
        sendReasoning: Bool? = nil,
        structuredOutputMode: AnthropicStructuredOutputMode? = nil,
        thinking: AnthropicThinkingOptions? = nil,
        disableParallelToolUse: Bool? = nil,
        cacheControl: AnthropicCacheControl? = nil,
        metadata: AnthropicMetadataOptions? = nil,
        mcpServers: [AnthropicMCPServer]? = nil,
        container: AnthropicContainerOptions? = nil,
        toolStreaming: Bool? = nil,
        effort: AnthropicEffort? = nil,
        taskBudget: AnthropicTaskBudget? = nil,
        speed: AnthropicSpeed? = nil,
        inferenceGeo: AnthropicInferenceGeo? = nil,
        fallbacks: [AnthropicFallback]? = nil,
        contextManagement: AnthropicContextManagement? = nil,
        anthropicBeta: [String]? = nil
    ) {
        self.sendReasoning = sendReasoning
        self.structuredOutputMode = structuredOutputMode
        self.thinking = thinking
        self.disableParallelToolUse = disableParallelToolUse
        self.cacheControl = cacheControl
        self.metadata = metadata
        self.mcpServers = mcpServers
        self.container = container
        self.toolStreaming = toolStreaming
        self.effort = effort
        self.taskBudget = taskBudget
        self.speed = speed
        self.inferenceGeo = inferenceGeo
        self.fallbacks = fallbacks
        self.contextManagement = contextManagement
        self.anthropicBeta = anthropicBeta
    }
}

public struct AnthropicFilePartProviderOptions: Sendable, Equatable {
    public struct Citations: Sendable, Equatable {
        public var enabled: Bool

        public init(enabled: Bool) {
            self.enabled = enabled
        }
    }

    public var containerUpload: Bool?
    public var citations: Citations?
    public var title: String?
    public var context: String?

    public init(
        containerUpload: Bool? = nil,
        citations: Citations? = nil,
        title: String? = nil,
        context: String? = nil
    ) {
        self.containerUpload = containerUpload
        self.citations = citations
        self.title = title
        self.context = context
    }
}

private func parseOptionalBool(_ dict: [String: JSONValue], key: String) throws -> Bool? {
    guard let value = dict[key], value != .null else { return nil }
    guard case .bool(let bool) = value else {
        throw TypeValidationError.wrap(value: value, cause: SchemaValidationIssuesError(vendor: "anthropic", issues: "\(key) must be a boolean"))
    }
    return bool
}

private func parseOptionalString(_ dict: [String: JSONValue], key: String) throws -> String? {
    guard let value = dict[key], value != .null else { return nil }
    guard case .string(let string) = value else {
        throw TypeValidationError.wrap(value: value, cause: SchemaValidationIssuesError(vendor: "anthropic", issues: "\(key) must be a string"))
    }
    return string
}

private func parseOptionalStringArray(_ dict: [String: JSONValue], key: String) throws -> [String]? {
    guard let value = dict[key], value != .null else { return nil }
    guard case .array(let array) = value else {
        throw TypeValidationError.wrap(value: value, cause: SchemaValidationIssuesError(vendor: "anthropic", issues: "\(key) must be an array"))
    }
    var result: [String] = []
    result.reserveCapacity(array.count)
    for item in array {
        guard case .string(let string) = item else {
            throw TypeValidationError.wrap(value: value, cause: SchemaValidationIssuesError(vendor: "anthropic", issues: "\(key) must be an array of strings"))
        }
        result.append(string)
    }
    return result
}

private func parseOptionalInteger(
    _ dict: [String: JSONValue],
    key: String,
    minimum: Int? = nil
) throws -> Int? {
    guard let value = dict[key], value != .null else { return nil }
    guard case .number(let number) = value,
          let integer = Int(exactly: number),
          minimum.map({ integer >= $0 }) ?? true else {
        let minimumDescription = minimum.map { " greater than or equal to \($0)" } ?? ""
        throw TypeValidationError.wrap(
            value: value,
            cause: SchemaValidationIssuesError(
                vendor: "anthropic",
                issues: "\(key) must be an integer\(minimumDescription)"
            )
        )
    }
    return integer
}

private func parseOptionalObject(
    _ dict: [String: JSONValue],
    key: String
) throws -> [String: JSONValue]? {
    guard let value = dict[key], value != .null else { return nil }
    guard case .object(let object) = value else {
        throw TypeValidationError.wrap(
            value: value,
            cause: SchemaValidationIssuesError(vendor: "anthropic", issues: "\(key) must be an object")
        )
    }
    return object
}

private let anthropicProviderOptionsJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "additionalProperties": .bool(true)
])

public let anthropicProviderOptionsSchema = FlexibleSchema(
    Schema<AnthropicProviderOptions>(
        jsonSchemaResolver: { anthropicProviderOptionsJSONSchema },
        validator: { value in
            do {
                let json = try jsonValue(from: value)
                guard case .object(let dict) = json else {
                    let error = SchemaValidationIssuesError(vendor: "anthropic", issues: "provider options must be an object")
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                var options = AnthropicProviderOptions()
                options.sendReasoning = try parseOptionalBool(dict, key: "sendReasoning")

                if let structuredValue = dict["structuredOutputMode"], structuredValue != .null {
                    guard case .string(let raw) = structuredValue,
                          let mode = AnthropicStructuredOutputMode(rawValue: raw) else {
                        let error = SchemaValidationIssuesError(vendor: "anthropic", issues: "structuredOutputMode must be 'outputFormat', 'jsonTool', or 'auto'")
                        return .failure(error: TypeValidationError.wrap(value: structuredValue, cause: error))
                    }
                    options.structuredOutputMode = mode
                }

                if let thinkingValue = dict["thinking"], thinkingValue != .null {
                    guard case .object(let thinkingDict) = thinkingValue else {
                        let error = SchemaValidationIssuesError(vendor: "anthropic", issues: "thinking must be an object")
                        return .failure(error: TypeValidationError.wrap(value: thinkingValue, cause: error))
                    }

                    guard let typeValue = thinkingDict["type"], case .string(let typeRaw) = typeValue else {
                        let error = SchemaValidationIssuesError(vendor: "anthropic", issues: "thinking.type must be 'enabled', 'disabled', or 'adaptive'")
                        return .failure(error: TypeValidationError.wrap(value: thinkingValue, cause: error))
                    }

                    guard let mode = AnthropicThinkingOptions.Mode(rawValue: typeRaw) else {
                        let error = SchemaValidationIssuesError(vendor: "anthropic", issues: "thinking.type must be 'enabled', 'disabled', or 'adaptive'")
                        return .failure(error: TypeValidationError.wrap(value: thinkingValue, cause: error))
                    }

                    var budget: Int?
                    if let budgetValue = thinkingDict["budgetTokens"], budgetValue != .null {
                        guard case .number(let number) = budgetValue else {
                            let error = SchemaValidationIssuesError(vendor: "anthropic", issues: "thinking.budgetTokens must be a number")
                            return .failure(error: TypeValidationError.wrap(value: budgetValue, cause: error))
                        }
                        let intValue = Int(number)
                        if Double(intValue) != number {
                            let error = SchemaValidationIssuesError(vendor: "anthropic", issues: "thinking.budgetTokens must be an integer")
                            return .failure(error: TypeValidationError.wrap(value: budgetValue, cause: error))
                        }
                        budget = intValue
                    }

                    var display: AnthropicThinkingOptions.Display?
                    if let displayValue = thinkingDict["display"], displayValue != .null {
                        guard case .string(let raw) = displayValue,
                              let parsed = AnthropicThinkingOptions.Display(rawValue: raw) else {
                            let error = SchemaValidationIssuesError(vendor: "anthropic", issues: "thinking.display must be 'summarized' or 'omitted'")
                            return .failure(error: TypeValidationError.wrap(value: displayValue, cause: error))
                        }
                        display = parsed
                    }

                    options.thinking = AnthropicThinkingOptions(type: mode, budgetTokens: budget, display: display)
                }

                options.disableParallelToolUse = try parseOptionalBool(dict, key: "disableParallelToolUse")

                if let cacheValue = dict["cacheControl"], cacheValue != .null {
                    guard case .object(let cacheDict) = cacheValue else {
                        let error = SchemaValidationIssuesError(vendor: "anthropic", issues: "cacheControl must be an object")
                        return .failure(error: TypeValidationError.wrap(value: cacheValue, cause: error))
                    }

                    guard let typeValue = cacheDict["type"], case .string(let typeString) = typeValue, typeString == "ephemeral" else {
                        let error = SchemaValidationIssuesError(vendor: "anthropic", issues: "cacheControl.type must be 'ephemeral'")
                        return .failure(error: TypeValidationError.wrap(value: cacheValue, cause: error))
                    }

                    var ttl: AnthropicCacheControl.TTL?
                    if let ttlValue = cacheDict["ttl"], ttlValue != .null {
                        guard case .string(let ttlRaw) = ttlValue, let parsed = AnthropicCacheControl.TTL(rawValue: ttlRaw) else {
                            let error = SchemaValidationIssuesError(vendor: "anthropic", issues: "cacheControl.ttl must be '5m' or '1h'")
                            return .failure(error: TypeValidationError.wrap(value: ttlValue, cause: error))
                        }
                        ttl = parsed
                    }

                    var additional = cacheDict
                    additional.removeValue(forKey: "type")
                    if ttl != nil {
                        additional.removeValue(forKey: "ttl")
                    }

                    options.cacheControl = AnthropicCacheControl(
                        type: typeString,
                        ttl: ttl,
                        additionalFields: additional
                    )
                }

                if let metadataValue = dict["metadata"], metadataValue != .null {
                    guard case .object(let metadataDict) = metadataValue else {
                        let error = SchemaValidationIssuesError(vendor: "anthropic", issues: "metadata must be an object")
                        return .failure(error: TypeValidationError.wrap(value: metadataValue, cause: error))
                    }
                    options.metadata = AnthropicMetadataOptions(
                        userId: try parseOptionalString(metadataDict, key: "userId")
                    )
                }

                if let mcpServersValue = dict["mcpServers"], mcpServersValue != .null {
                    guard case .array(let serversArray) = mcpServersValue else {
                        let error = SchemaValidationIssuesError(vendor: "anthropic", issues: "mcpServers must be an array")
                        return .failure(error: TypeValidationError.wrap(value: mcpServersValue, cause: error))
                    }

                    var servers: [AnthropicMCPServer] = []
                    servers.reserveCapacity(serversArray.count)
                    for serverValue in serversArray {
                        guard case .object(let serverDict) = serverValue else {
                            let error = SchemaValidationIssuesError(vendor: "anthropic", issues: "mcpServers must be an array of objects")
                            return .failure(error: TypeValidationError.wrap(value: mcpServersValue, cause: error))
                        }

                        guard let typeValue = serverDict["type"],
                              case .string(let typeRaw) = typeValue,
                              let type = AnthropicMCPServer.ServerType(rawValue: typeRaw) else {
                            let error = SchemaValidationIssuesError(vendor: "anthropic", issues: "mcpServers[].type must be 'url'")
                            return .failure(error: TypeValidationError.wrap(value: serverValue, cause: error))
                        }

                        guard let nameValue = serverDict["name"], case .string(let name) = nameValue else {
                            let error = SchemaValidationIssuesError(vendor: "anthropic", issues: "mcpServers[].name must be a string")
                            return .failure(error: TypeValidationError.wrap(value: serverValue, cause: error))
                        }

                        guard let urlValue = serverDict["url"], case .string(let url) = urlValue else {
                            let error = SchemaValidationIssuesError(vendor: "anthropic", issues: "mcpServers[].url must be a string")
                            return .failure(error: TypeValidationError.wrap(value: serverValue, cause: error))
                        }

                        let authorizationToken = try parseOptionalString(serverDict, key: "authorizationToken")

                        var toolConfiguration: AnthropicMCPServer.ToolConfiguration? = nil
                        if let toolConfigurationValue = serverDict["toolConfiguration"], toolConfigurationValue != .null {
                            guard case .object(let toolConfigurationDict) = toolConfigurationValue else {
                                let error = SchemaValidationIssuesError(vendor: "anthropic", issues: "mcpServers[].toolConfiguration must be an object")
                                return .failure(error: TypeValidationError.wrap(value: toolConfigurationValue, cause: error))
                            }

                            toolConfiguration = AnthropicMCPServer.ToolConfiguration(
                                enabled: try parseOptionalBool(toolConfigurationDict, key: "enabled"),
                                allowedTools: try parseOptionalStringArray(toolConfigurationDict, key: "allowedTools")
                            )
                        }

                        servers.append(
                            AnthropicMCPServer(
                                type: type,
                                name: name,
                                url: url,
                                authorizationToken: authorizationToken,
                                toolConfiguration: toolConfiguration
                            )
                        )
                    }
                    options.mcpServers = servers
                }

                if let containerValue = dict["container"], containerValue != .null {
                    guard case .object(let containerDict) = containerValue else {
                        let error = SchemaValidationIssuesError(vendor: "anthropic", issues: "container must be an object")
                        return .failure(error: TypeValidationError.wrap(value: containerValue, cause: error))
                    }

                    var skills: [AnthropicContainerOptions.Skill]? = nil
                    if let skillsValue = containerDict["skills"], skillsValue != .null {
                        guard case .array(let skillsArray) = skillsValue else {
                            let error = SchemaValidationIssuesError(vendor: "anthropic", issues: "container.skills must be an array")
                            return .failure(error: TypeValidationError.wrap(value: skillsValue, cause: error))
                        }

                        var parsedSkills: [AnthropicContainerOptions.Skill] = []
                        parsedSkills.reserveCapacity(skillsArray.count)
                        for skillValue in skillsArray {
                            guard case .object(let skillDict) = skillValue else {
                                let error = SchemaValidationIssuesError(vendor: "anthropic", issues: "container.skills must be an array of objects")
                                return .failure(error: TypeValidationError.wrap(value: skillsValue, cause: error))
                            }

                            guard let typeValue = skillDict["type"],
                                  case .string(let typeRaw) = typeValue,
                                  let type = AnthropicContainerOptions.Skill.SkillType(rawValue: typeRaw) else {
                                let error = SchemaValidationIssuesError(vendor: "anthropic", issues: "container.skills[].type must be 'anthropic' or 'custom'")
                                return .failure(error: TypeValidationError.wrap(value: skillValue, cause: error))
                            }

                            guard let skillIdValue = skillDict["skillId"], case .string(let skillId) = skillIdValue else {
                                let error = SchemaValidationIssuesError(vendor: "anthropic", issues: "container.skills[].skillId must be a string")
                                return .failure(error: TypeValidationError.wrap(value: skillValue, cause: error))
                            }

                            let version = try parseOptionalString(skillDict, key: "version")

                            parsedSkills.append(.init(type: type, skillId: skillId, version: version))
                        }

                        skills = parsedSkills
                    }

                    options.container = AnthropicContainerOptions(
                        id: try parseOptionalString(containerDict, key: "id"),
                        skills: skills
                    )
                }

                options.toolStreaming = try parseOptionalBool(dict, key: "toolStreaming")

                if let effortValue = dict["effort"], effortValue != .null {
                    guard case .string(let raw) = effortValue,
                          let effort = AnthropicEffort(rawValue: raw) else {
                        let error = SchemaValidationIssuesError(vendor: "anthropic", issues: "effort must be 'low', 'medium', 'high', 'xhigh', or 'max'")
                        return .failure(error: TypeValidationError.wrap(value: effortValue, cause: error))
                    }
                    options.effort = effort
                }

                if let taskBudgetValue = dict["taskBudget"], taskBudgetValue != .null {
                    guard case .object(let taskBudgetDict) = taskBudgetValue else {
                        let error = SchemaValidationIssuesError(vendor: "anthropic", issues: "taskBudget must be an object")
                        return .failure(error: TypeValidationError.wrap(value: taskBudgetValue, cause: error))
                    }
                    guard let typeValue = taskBudgetDict["type"],
                          case .string(let typeRaw) = typeValue,
                          let type = AnthropicTaskBudget.BudgetType(rawValue: typeRaw) else {
                        let error = SchemaValidationIssuesError(vendor: "anthropic", issues: "taskBudget.type must be 'tokens'")
                        return .failure(error: TypeValidationError.wrap(value: taskBudgetValue, cause: error))
                    }
                    guard let total = try parseOptionalInteger(taskBudgetDict, key: "total", minimum: 20_000) else {
                        let error = SchemaValidationIssuesError(vendor: "anthropic", issues: "taskBudget.total is required")
                        return .failure(error: TypeValidationError.wrap(value: taskBudgetValue, cause: error))
                    }
                    options.taskBudget = AnthropicTaskBudget(
                        type: type,
                        total: total,
                        remaining: try parseOptionalInteger(taskBudgetDict, key: "remaining", minimum: 0)
                    )
                }

                if let speedValue = dict["speed"], speedValue != .null {
                    guard case .string(let raw) = speedValue,
                          let speed = AnthropicSpeed(rawValue: raw) else {
                        let error = SchemaValidationIssuesError(vendor: "anthropic", issues: "speed must be 'fast' or 'standard'")
                        return .failure(error: TypeValidationError.wrap(value: speedValue, cause: error))
                    }
                    options.speed = speed
                }

                if let inferenceGeoValue = dict["inferenceGeo"], inferenceGeoValue != .null {
                    guard case .string(let raw) = inferenceGeoValue,
                          let inferenceGeo = AnthropicInferenceGeo(rawValue: raw) else {
                        let error = SchemaValidationIssuesError(vendor: "anthropic", issues: "inferenceGeo must be 'us' or 'global'")
                        return .failure(error: TypeValidationError.wrap(value: inferenceGeoValue, cause: error))
                    }
                    options.inferenceGeo = inferenceGeo
                }

                if let fallbacksValue = dict["fallbacks"], fallbacksValue != .null {
                    guard case .array(let fallbackValues) = fallbacksValue else {
                        let error = SchemaValidationIssuesError(vendor: "anthropic", issues: "fallbacks must be an array")
                        return .failure(error: TypeValidationError.wrap(value: fallbacksValue, cause: error))
                    }

                    var fallbacks: [AnthropicFallback] = []
                    fallbacks.reserveCapacity(fallbackValues.count)
                    for fallbackValue in fallbackValues {
                        guard case .object(let fallbackDict) = fallbackValue,
                              let modelValue = fallbackDict["model"],
                              case .string(let model) = modelValue else {
                            let error = SchemaValidationIssuesError(vendor: "anthropic", issues: "fallbacks[].model must be a string")
                            return .failure(error: TypeValidationError.wrap(value: fallbackValue, cause: error))
                        }

                        var fallbackSpeed: AnthropicSpeed?
                        if let speedValue = fallbackDict["speed"], speedValue != .null {
                            guard case .string(let raw) = speedValue,
                                  let speed = AnthropicSpeed(rawValue: raw) else {
                                let error = SchemaValidationIssuesError(vendor: "anthropic", issues: "fallbacks[].speed must be 'fast' or 'standard'")
                                return .failure(error: TypeValidationError.wrap(value: speedValue, cause: error))
                            }
                            fallbackSpeed = speed
                        }

                        fallbacks.append(AnthropicFallback(
                            model: model,
                            maxTokens: try parseOptionalInteger(fallbackDict, key: "max_tokens"),
                            thinking: try parseOptionalObject(fallbackDict, key: "thinking"),
                            outputConfig: try parseOptionalObject(fallbackDict, key: "output_config"),
                            speed: fallbackSpeed
                        ))
                    }
                    options.fallbacks = fallbacks
                }

                if let contextManagementValue = dict["contextManagement"], contextManagementValue != .null {
                    guard case .object(let contextDict) = contextManagementValue else {
                        let error = SchemaValidationIssuesError(vendor: "anthropic", issues: "contextManagement must be an object")
                        return .failure(error: TypeValidationError.wrap(value: contextManagementValue, cause: error))
                    }

                    guard let editsValue = contextDict["edits"], case .array(let editsArray) = editsValue else {
                        let error = SchemaValidationIssuesError(vendor: "anthropic", issues: "contextManagement.edits must be an array")
                        return .failure(error: TypeValidationError.wrap(value: contextManagementValue, cause: error))
                    }

                    var edits: [AnthropicContextManagement.Edit] = []
                    edits.reserveCapacity(editsArray.count)
                    for editValue in editsArray {
                        guard case .object(let editDict) = editValue else {
                            let error = SchemaValidationIssuesError(vendor: "anthropic", issues: "contextManagement.edits must be an array of objects")
                            return .failure(error: TypeValidationError.wrap(value: editsValue, cause: error))
                        }

                        guard let typeValue = editDict["type"], case .string(let type) = typeValue else {
                            let error = SchemaValidationIssuesError(vendor: "anthropic", issues: "contextManagement.edits[].type must be a string")
                            return .failure(error: TypeValidationError.wrap(value: editValue, cause: error))
                        }

                        switch type {
                        case "clear_tool_uses_20250919":
                            var trigger: AnthropicContextManagement.ClearToolUses20250919.Trigger? = nil
                            if let triggerValue = editDict["trigger"], triggerValue != .null {
                                guard case .object(let triggerDict) = triggerValue,
                                      let triggerTypeValue = triggerDict["type"],
                                      case .string(let triggerTypeRaw) = triggerTypeValue,
                                      let triggerType = AnthropicContextManagement.ClearToolUses20250919.Trigger.TriggerType(rawValue: triggerTypeRaw),
                                      let triggerNumber = triggerDict["value"],
                                      case .number(let triggerValueNumber) = triggerNumber else {
                                    let error = SchemaValidationIssuesError(vendor: "anthropic", issues: "contextManagement.edits[].trigger must be a valid trigger object")
                                    return .failure(error: TypeValidationError.wrap(value: triggerValue, cause: error))
                                }
                                trigger = .init(type: triggerType, value: triggerValueNumber)
                            }

                            var keep: AnthropicContextManagement.ClearToolUses20250919.Keep? = nil
                            if let keepValue = editDict["keep"], keepValue != .null {
                                guard case .object(let keepDict) = keepValue,
                                      let keepTypeValue = keepDict["type"],
                                      case .string(let keepTypeRaw) = keepTypeValue,
                                      keepTypeRaw == "tool_uses",
                                      let keepNumber = keepDict["value"],
                                      case .number(let keepValueNumber) = keepNumber else {
                                    let error = SchemaValidationIssuesError(vendor: "anthropic", issues: "contextManagement.edits[].keep must be a valid keep object")
                                    return .failure(error: TypeValidationError.wrap(value: keepValue, cause: error))
                                }
                                keep = .init(value: keepValueNumber)
                            }

                            var clearAtLeast: AnthropicContextManagement.ClearToolUses20250919.ClearAtLeast? = nil
                            if let clearAtLeastValue = editDict["clearAtLeast"], clearAtLeastValue != .null {
                                guard case .object(let clearDict) = clearAtLeastValue,
                                      let clearTypeValue = clearDict["type"],
                                      case .string(let clearTypeRaw) = clearTypeValue,
                                      clearTypeRaw == "input_tokens",
                                      let clearNumber = clearDict["value"],
                                      case .number(let clearValueNumber) = clearNumber else {
                                    let error = SchemaValidationIssuesError(vendor: "anthropic", issues: "contextManagement.edits[].clearAtLeast must be a valid clearAtLeast object")
                                    return .failure(error: TypeValidationError.wrap(value: clearAtLeastValue, cause: error))
                                }
                                clearAtLeast = .init(value: clearValueNumber)
                            }

                            let clearToolInputs = try parseOptionalBool(editDict, key: "clearToolInputs")
                            let excludeTools = try parseOptionalStringArray(editDict, key: "excludeTools")

                            edits.append(
                                .clearToolUses20250919(
                                    .init(
                                        trigger: trigger,
                                        keep: keep,
                                        clearAtLeast: clearAtLeast,
                                        clearToolInputs: clearToolInputs,
                                        excludeTools: excludeTools
                                    )
                                )
                            )

                        case "clear_thinking_20251015":
                            var keep: AnthropicContextManagement.ClearThinking20251015.Keep? = nil
                            if let keepValue = editDict["keep"], keepValue != .null {
                                if case .string(let keepRaw) = keepValue {
                                    guard keepRaw == "all" else {
                                        let error = SchemaValidationIssuesError(vendor: "anthropic", issues: "contextManagement.edits[].keep must be 'all' or a keep object")
                                        return .failure(error: TypeValidationError.wrap(value: keepValue, cause: error))
                                    }
                                    keep = .all
                                } else if case .object(let keepDict) = keepValue,
                                          let keepTypeValue = keepDict["type"],
                                          case .string(let keepTypeRaw) = keepTypeValue,
                                          keepTypeRaw == "thinking_turns",
                                          let keepNumber = keepDict["value"],
                                          case .number(let keepNumberValue) = keepNumber {
                                    keep = .thinkingTurns(keepNumberValue)
                                } else {
                                    let error = SchemaValidationIssuesError(vendor: "anthropic", issues: "contextManagement.edits[].keep must be 'all' or a keep object")
                                    return .failure(error: TypeValidationError.wrap(value: keepValue, cause: error))
                                }
                            }

                            edits.append(.clearThinking20251015(.init(keep: keep)))

                        case "compact_20260112":
                            var trigger: AnthropicContextManagement.Compact20260112.Trigger? = nil
                            if let triggerValue = editDict["trigger"], triggerValue != .null {
                                guard case .object(let triggerDict) = triggerValue,
                                      let triggerNumber = triggerDict["value"],
                                      case .number(let triggerValueNumber) = triggerNumber else {
                                    let error = SchemaValidationIssuesError(vendor: "anthropic", issues: "contextManagement.edits[].trigger must be a valid trigger object")
                                    return .failure(error: TypeValidationError.wrap(value: triggerValue, cause: error))
                                }
                                trigger = .init(value: triggerValueNumber)
                            }

                            let pauseAfterCompaction = try parseOptionalBool(editDict, key: "pauseAfterCompaction")
                            let instructions = try parseOptionalString(editDict, key: "instructions")

                            edits.append(
                                .compact20260112(
                                    .init(
                                        trigger: trigger,
                                        pauseAfterCompaction: pauseAfterCompaction,
                                        instructions: instructions
                                    )
                                )
                            )

                        default:
                            let error = SchemaValidationIssuesError(vendor: "anthropic", issues: "Unknown context management strategy: \(type)")
                            return .failure(error: TypeValidationError.wrap(value: editValue, cause: error))
                        }
                    }

                    options.contextManagement = AnthropicContextManagement(edits: edits)
                }

                if let anthropicBetaValue = dict["anthropicBeta"], anthropicBetaValue != .null {
                    guard case .array(let array) = anthropicBetaValue else {
                        let error = SchemaValidationIssuesError(vendor: "anthropic", issues: "anthropicBeta must be an array of strings")
                        return .failure(error: TypeValidationError.wrap(value: anthropicBetaValue, cause: error))
                    }
                    var betas: [String] = []
                    betas.reserveCapacity(array.count)
                    for item in array {
                        guard case .string(let beta) = item else {
                            let error = SchemaValidationIssuesError(vendor: "anthropic", issues: "anthropicBeta entries must be strings")
                            return .failure(error: TypeValidationError.wrap(value: item, cause: error))
                        }
                        betas.append(beta)
                    }
                    options.anthropicBeta = betas
                }

                return .success(value: options)
            } catch {
                return .failure(error: TypeValidationError.wrap(value: value, cause: error))
            }
        }
    )
)

private let anthropicFilePartOptionsJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "additionalProperties": .bool(true)
])

public let anthropicFilePartProviderOptionsSchema = FlexibleSchema(
    Schema<AnthropicFilePartProviderOptions>(
        jsonSchemaResolver: { anthropicFilePartOptionsJSONSchema },
        validator: { value in
            do {
                let json = try jsonValue(from: value)
                guard case .object(let dict) = json else {
                    let error = SchemaValidationIssuesError(vendor: "anthropic", issues: "file part options must be an object")
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                var options = AnthropicFilePartProviderOptions()

                options.containerUpload = try parseOptionalBool(dict, key: "containerUpload")

                if let citationsValue = dict["citations"], citationsValue != .null {
                    guard case .object(let citationsDict) = citationsValue else {
                        let error = SchemaValidationIssuesError(vendor: "anthropic", issues: "citations must be an object")
                        return .failure(error: TypeValidationError.wrap(value: citationsValue, cause: error))
                    }

                    guard let enabledValue = citationsDict["enabled"], case .bool(let enabled) = enabledValue else {
                        let error = SchemaValidationIssuesError(vendor: "anthropic", issues: "citations.enabled must be a boolean")
                        return .failure(error: TypeValidationError.wrap(value: citationsValue, cause: error))
                    }

                    options.citations = .init(enabled: enabled)
                }

                options.title = try parseOptionalString(dict, key: "title")
                options.context = try parseOptionalString(dict, key: "context")

                return .success(value: options)
            } catch {
                return .failure(error: TypeValidationError.wrap(value: value, cause: error))
            }
        }
    )
)
