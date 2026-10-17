import Foundation
import AISDKProvider
import AISDKProviderUtils

struct OpenAIResponsesPreparedTools: Sendable {
    let tools: [JSONValue]?
    let toolChoice: JSONValue?
    let warnings: [SharedV4Warning]
    var outputSchemaToolNames: Set<Data> = []
}

func prepareOpenAIResponsesTools(
    tools: [LanguageModelV4Tool]?,
    toolChoice: LanguageModelV4ToolChoice?,
    allowedTools: OpenAIResponsesAllowedTools? = nil,
    toolNameMapping: ToolNameMapping = .init(),
    customProviderToolNames: Set<Data> = [],
    supportsAsyncToolCalling: Bool = true
) async throws -> OpenAIResponsesPreparedTools {
    guard let tools, !tools.isEmpty else {
        return OpenAIResponsesPreparedTools(tools: nil, toolChoice: nil, warnings: [])
    }

    var warnings: [SharedV4Warning] = []
    var openAITools: [JSONValue] = []
    var namespaceTools: [Data: (description: String, index: Int, tools: [JSONValue])] = [:]
    var resolvedCustomProviderToolNames = customProviderToolNames
    var outputSchemaToolNames: Set<Data> = []
    var resolutions: [Data: AllowedToolResolution] = [:]
    var aliases: [Data: AllowedToolResolution] = [:]

    func record(_ name: String, _ resolution: AllowedToolResolution, canonical: String? = nil) {
        resolutions[Data(name.utf8)] = resolution
        guard let canonical, !canonical.utf8.elementsEqual(name.utf8) else { return }
        let key = Data(canonical.utf8)
        if let existing = aliases[key], existing != resolution { aliases[key] = .ambiguous }
        else { aliases[key] = resolution }
    }

    for tool in tools {
        switch tool {
        case .function(let functionTool):
            let openAIOptions = parseOpenAIToolOptions(functionTool.providerOptions)
            let asyncValue = resolveAsyncToolOption(openAIOptions.async, supported: supportsAsyncToolCalling, name: functionTool.name, warnings: &warnings)
            let normalized = try normalizeOpenAIJsonSchema(functionTool.inputSchema)
            warnings.append(contentsOf: normalized.warnings)
            var payload: [String: JSONValue] = [
                "type": .string("function"),
                "name": .string(functionTool.name),
                "parameters": normalized.schema,
                "strict": .bool(functionTool.strict ?? false)
            ]
            if let outputSchema = openAIOptions.outputSchema {
                outputSchemaToolNames.insert(Data(functionTool.name.utf8))
                let normalized = try normalizeOpenAIJsonSchema(outputSchema)
                payload["output_schema"] = normalized.schema
                warnings.append(contentsOf: normalized.warnings)
            }
            if let allowedCallers = openAIOptions.allowedCallers { payload["allowed_callers"] = allowedCallers }
            if let asyncValue { payload["async"] = .bool(asyncValue) }
            if let description = functionTool.description {
                payload["description"] = .string(description)
            }
            if let deferLoading = openAIOptions.deferLoading {
                payload["defer_loading"] = .bool(deferLoading)
            }

            if let namespace = openAIOptions.namespace {
                if let description = namespaceTools[Data(namespace.name.utf8)]?.description {
                    guard description.utf8.elementsEqual(namespace.description.utf8) else {
                        throw UnsupportedFunctionalityError(functionality: "conflicting descriptions for OpenAI tool namespace \"\(namespace.name)\"")
                    }
                    namespaceTools[Data(namespace.name.utf8)]?.tools.append(.object(payload))
                } else {
                    let index = openAITools.count
                    namespaceTools[Data(namespace.name.utf8)] = (namespace.description, index, [.object(payload)])
                    openAITools.append(.object([
                        "type": .string("namespace"),
                        "name": .string(namespace.name),
                        "description": .string(namespace.description),
                        "tools": .array([])
                    ]))
                }
            } else {
                openAITools.append(.object(payload))
            }

            record(functionTool.name, openAIOptions.namespace != nil
                ? .unsupported("tools inside an OpenAI tool namespace are not visible to tool_choice.allowed_tools")
                : openAIOptions.deferLoading == true
                    ? .unsupported("deferred tools are not visible to tool_choice.allowed_tools")
                    : .supported(type: "function", identity: functionTool.name))

        case .provider(let providerTool):
            let previousCount = openAITools.count
            switch providerTool.id {
            case "openai.file_search":
                let parsed = try await validateTypes(
                    ValidateTypesOptions(value: providerTool.args, schema: openaiFileSearchArgsSchema)
                )
                let rankingOptions: JSONValue?
                if let ranking = parsed.ranking {
                    var rankingPayload: [String: JSONValue] = [:]
                    if let ranker = ranking.ranker {
                        rankingPayload["ranker"] = .string(ranker)
                    }
                    if let threshold = ranking.scoreThreshold {
                        rankingPayload["score_threshold"] = .number(threshold)
                    }
                    rankingOptions = .object(rankingPayload)
                } else {
                    rankingOptions = nil
                }

                var payload: [String: JSONValue] = [
                    "type": .string("file_search"),
                    "vector_store_ids": .array(parsed.vectorStoreIds.map(JSONValue.string))
                ]
                if let max = parsed.maxNumResults {
                    payload["max_num_results"] = .number(Double(max))
                }
                if let rankingOptions {
                    payload["ranking_options"] = rankingOptions
                }
                if let filters = parsed.filters {
                    payload["filters"] = filters
                }
                openAITools.append(.object(payload))

            case "openai.local_shell":
                openAITools.append(.object([
                    "type": .string("local_shell")
                ]))

            case "openai.shell":
                let parsed = try await validateTypes(
                    ValidateTypesOptions(value: providerTool.args, schema: openaiShellArgsSchema)
                )
                var payload: [String: JSONValue] = [
                    "type": .string("shell")
                ]
                if let environment = parsed.environment {
                    payload["environment"] = try mapShellEnvironment(environment)
                }
                openAITools.append(.object(payload))

            case "openai.apply_patch":
                openAITools.append(.object([
                    "type": .string("apply_patch")
                ]))

            case "openai.computer":
                openAITools.append(.object(["type": .string("computer")]))

            case "openai.programmatic_tool_calling":
                openAITools.append(.object(["type": .string("programmatic_tool_calling")]))

            case "openai.web_search_preview":
                let parsed = try await validateTypes(
                    ValidateTypesOptions(value: providerTool.args, schema: openaiWebSearchPreviewArgsSchema)
                )
                var payload: [String: JSONValue] = [
                    "type": .string("web_search_preview")
                ]
                if let size = parsed.searchContextSize {
                    payload["search_context_size"] = .string(size)
                }
                if let location = parsed.userLocation {
                    payload["user_location"] = makeUserLocationJSON(location)
                }
                openAITools.append(.object(payload))

            case "openai.web_search":
                let parsed = try await validateTypes(
                    ValidateTypesOptions(value: providerTool.args, schema: openaiWebSearchArgsSchema)
                )
                var payload: [String: JSONValue] = [
                    "type": .string("web_search")
                ]
                if let filters = parsed.filters {
                    var filtersPayload: [String: JSONValue] = [:]
                    if let allowed = filters.allowedDomains {
                        filtersPayload["allowed_domains"] = .array(allowed.map(JSONValue.string))
                    }
                    if let blocked = filters.blockedDomains {
                        filtersPayload["blocked_domains"] = .array(blocked.map(JSONValue.string))
                    }
                    payload["filters"] = .object(filtersPayload)
                }
                if let externalWebAccess = parsed.externalWebAccess {
                    payload["external_web_access"] = .bool(externalWebAccess)
                }
                if let size = parsed.searchContextSize {
                    payload["search_context_size"] = .string(size)
                }
                if let location = parsed.userLocation {
                    payload["user_location"] = makeUserLocationJSON(location)
                }
                openAITools.append(.object(payload))

            case "openai.code_interpreter":
                let parsed = try await validateTypes(
                    ValidateTypesOptions(value: providerTool.args, schema: openaiCodeInterpreterArgsSchema)
                )
                var containerJSON: JSONValue
                if let container = parsed.container {
                    switch container {
                    case .string(let value):
                        containerJSON = .string(value)
                    case .auto(let fileIds):
                        var payload: [String: JSONValue] = [
                            "type": .string("auto")
                        ]
                        if let fileIds {
                            payload["file_ids"] = .array(fileIds.map(JSONValue.string))
                        }
                        containerJSON = .object(payload)
                    }
                } else {
                    containerJSON = .object([
                        "type": .string("auto")
                    ])
                }

                openAITools.append(.object([
                    "type": .string("code_interpreter"),
                    "container": containerJSON
                ]))

            case "openai.image_generation":
                let parsed = try await validateTypes(
                    ValidateTypesOptions(value: providerTool.args, schema: openaiImageGenerationArgsSchema)
                )
                var payload: [String: JSONValue] = [
                    "type": .string("image_generation")
                ]
                if let action = parsed.action { payload["action"] = .string(action) }
                if let background = parsed.background {
                    payload["background"] = .string(background)
                }
                if let fidelity = parsed.inputFidelity {
                    payload["input_fidelity"] = .string(fidelity)
                }
                if let mask = parsed.inputImageMask {
                    var maskPayload: [String: JSONValue] = [:]
                    if let fileId = mask.fileId {
                        maskPayload["file_id"] = .string(fileId)
                    }
                    if let imageUrl = mask.imageUrl {
                        maskPayload["image_url"] = .string(imageUrl)
                    }
                    payload["input_image_mask"] = .object(maskPayload)
                }
                if let model = parsed.model {
                    payload["model"] = .string(model)
                }
                if let moderation = parsed.moderation {
                    payload["moderation"] = .string(moderation)
                }
                if let compression = parsed.outputCompression {
                    payload["output_compression"] = .number(Double(compression))
                }
                if let format = parsed.outputFormat {
                    payload["output_format"] = .string(format)
                }
                if let partial = parsed.partialImages {
                    payload["partial_images"] = .number(Double(partial))
                }
                if let quality = parsed.quality {
                    payload["quality"] = .string(quality)
                }
                if let size = parsed.size {
                    payload["size"] = .string(size)
                }
                openAITools.append(.object(payload))

            case "openai.mcp":
                let parsed = try await validateTypes(
                    ValidateTypesOptions(value: providerTool.args, schema: openaiMcpArgsSchema)
                )

                let allowedTools: JSONValue?
                if let parsedAllowedTools = parsed.allowedTools {
                    switch parsedAllowedTools {
                    case .toolNames(let names):
                        allowedTools = .array(names.map(JSONValue.string))
                    case .filter(let filter):
                        var filterPayload: [String: JSONValue] = [:]
                        if let readOnly = filter.readOnly {
                            filterPayload["read_only"] = .bool(readOnly)
                        }
                        if let toolNames = filter.toolNames {
                            filterPayload["tool_names"] = .array(toolNames.map(JSONValue.string))
                        }
                        allowedTools = .object(filterPayload)
                    }
                } else {
                    allowedTools = nil
                }

                let requireApprovalParam: JSONValue?
                if let requireApproval = parsed.requireApproval {
                    switch requireApproval {
                    case .always:
                        requireApprovalParam = .string("always")
                    case .never:
                        requireApprovalParam = .string("never")
                    case .conditional(let conditional):
                        if let never = conditional.never {
                            var neverPayload: [String: JSONValue] = [:]
                            if let toolNames = never.toolNames {
                                neverPayload["tool_names"] = .array(toolNames.map(JSONValue.string))
                            }
                            requireApprovalParam = .object([
                                "never": .object(neverPayload)
                            ])
                        } else {
                            requireApprovalParam = nil
                        }
                    }
                } else {
                    requireApprovalParam = nil
                }

                var payload: [String: JSONValue] = [
                    "type": .string("mcp"),
                    "server_label": .string(parsed.serverLabel),
                    "require_approval": requireApprovalParam ?? .string("never")
                ]
                if let allowedTools {
                    payload["allowed_tools"] = allowedTools
                }
                if let authorization = parsed.authorization {
                    payload["authorization"] = .string(authorization)
                }
                if let connectorId = parsed.connectorId {
                    payload["connector_id"] = .string(connectorId)
                }
                if let headers = parsed.headers {
                    payload["headers"] = .object(headers.mapValues(JSONValue.string))
                }
                if let serverDescription = parsed.serverDescription {
                    payload["server_description"] = .string(serverDescription)
                }
                if let serverUrl = parsed.serverUrl {
                    payload["server_url"] = .string(serverUrl)
                }
                openAITools.append(.object(payload))

            case "openai.custom":
                let parsed: OpenAICustomToolArgs = try await validateTypes(
                    ValidateTypesOptions(value: providerTool.args, schema: openaiCustomArgsSchema)
                )

                var payload: [String: JSONValue] = [
                    "type": .string("custom"),
                    "name": .string(providerTool.name)
                ]
                if let description = parsed.description {
                    payload["description"] = .string(description)
                }
                if let value = resolveAsyncToolOption(parsed.async, supported: supportsAsyncToolCalling, name: providerTool.name, warnings: &warnings) {
                    payload["async"] = .bool(value)
                }
                if let format = parsed.format {
                    switch format {
                    case .grammar(let syntax, let definition):
                        payload["format"] = .object([
                            "type": .string("grammar"),
                            "syntax": .string(syntax.rawValue),
                            "definition": .string(definition)
                        ])
                    case .text:
                        payload["format"] = .object([
                            "type": .string("text")
                        ])
                    }
                }
                openAITools.append(.object(payload))
                resolvedCustomProviderToolNames.insert(Data(providerTool.name.utf8))

            case "openai.tool_search":
                let parsed = try await validateTypes(
                    ValidateTypesOptions(value: providerTool.args, schema: openaiToolSearchArgsSchema)
                )
                var payload: [String: JSONValue] = [
                    "type": .string("tool_search")
                ]
                if let execution = parsed.execution {
                    payload["execution"] = .string(execution.rawValue)
                }
                if let description = parsed.description {
                    payload["description"] = .string(description)
                }
                if let parameters = parsed.parameters {
                    payload["parameters"] = parameters
                }
                openAITools.append(.object(payload))

            default:
                break
            }
            if openAITools.count > previousCount {
                record(providerTool.name, allowedToolResolution(openAITools[previousCount]), canonical: toolNameMapping.toProviderToolName(providerTool.name))
            }
        }
    }

    for namespace in namespaceTools.values {
        guard case .object(var object) = openAITools[namespace.index] else { preconditionFailure() }
        object["tools"] = .array(namespace.tools)
        openAITools[namespace.index] = .object(object)
    }
    let finalTools = openAITools
    let finalToolChoice: JSONValue?
    if let allowedTools {
        var entries: [JSONValue] = []
        var dropped: [String] = []
        for name in allowedTools.toolNames {
            let key = Data(name.utf8)
            let direct = resolutions[key]
            let resolution = direct ?? aliases[key]
            func warn(_ details: String) {
                warnings.append(.unsupported(feature: "allowedTools entry \"\(name)\"", details: details))
            }
            if direct != nil, aliases[key] != nil {
                warn("this name is both a tool name and the provider tool name of another tool in this request; the tool with this name is allowed")
            }
            switch resolution {
            case .ambiguous:
                warn("several tools in this request share this provider tool name; use the tool name from the tools for this request instead")
                dropped.append(name)
            case .unsupported(let reason):
                warn("\(reason); the tool is removed from the allowed tools")
                dropped.append(name)
            case .supported(let type, let identity):
                var entry: [String: JSONValue] = ["type": .string(type)]
                if let identity { entry[type == "mcp" ? "server_label" : "name"] = .string(identity) }
                entries.append(.object(entry))
            case nil:
                warn("the tool is not part of the tools for this request and is sent as a function tool")
                entries.append(.object(["type": .string("function"), "name": .string(toolNameMapping.toProviderToolName(name))]))
            }
        }
        guard !entries.isEmpty else {
            throw UnsupportedFunctionalityError(functionality: "allowedTools with only tools that cannot be allow-listed (\(dropped.joined(separator: ", ")))")
        }
        finalToolChoice = .object([
            "type": .string("allowed_tools"), "mode": .string(allowedTools.mode ?? "auto"), "tools": .array(entries)
        ])
    } else {
        finalToolChoice = try mapToolChoice(
            toolChoice,
            toolNameMapping: toolNameMapping,
            customProviderToolNames: resolvedCustomProviderToolNames
        )
    }

    return OpenAIResponsesPreparedTools(tools: finalTools, toolChoice: finalToolChoice, warnings: warnings, outputSchemaToolNames: outputSchemaToolNames)
}

private enum AllowedToolResolution: Equatable {
    case supported(type: String, identity: String? = nil)
    case unsupported(String)
    case ambiguous

    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case let (.supported(a, x), .supported(b, y)):
            return a == b && x.map { Data($0.utf8) } == y.map { Data($0.utf8) }
        case let (.unsupported(a), .unsupported(b)): return a == b
        case (.ambiguous, .ambiguous): return true
        default: return false
        }
    }
}

private func allowedToolResolution(_ tool: JSONValue) -> AllowedToolResolution {
    guard case .object(let object) = tool, case .string(let type)? = object["type"] else { preconditionFailure() }
    switch type {
    case "custom": return .supported(type: type, identity: object["name"]?.stringValue)
    case "mcp": return .supported(type: type, identity: object["server_label"]?.stringValue)
    case "file_search", "web_search", "web_search_preview", "image_generation", "code_interpreter", "apply_patch", "shell", "local_shell", "computer", "programmatic_tool_calling":
        return .supported(type: type)
    default: return .unsupported("OpenAI does not support \(type) tools in tool_choice.allowed_tools")
    }
}

private func resolveAsyncToolOption(_ value: Bool?, supported: Bool, name: String, warnings: inout [SharedV4Warning]) -> Bool? {
    guard value == true, !supported else { return value }
    warnings.append(.unsupported(feature: "async tool calling for \"\(name)\"", details: "Async tool calling is only supported by GPT-6 and later models."))
    return nil
}

public struct OpenAIToolOptions: Sendable, Equatable {
    public struct Namespace: Sendable, Equatable {
        public let name: String
        public let description: String
        public init(name: String, description: String) { self.name = name; self.description = description }
    }

    public var deferLoading: Bool?
    public var namespace: Namespace?
    public var async: Bool?
    public var allowedCallers: JSONValue?
    public var outputSchema: JSONValue?

    public init(deferLoading: Bool? = nil, namespace: Namespace? = nil, async: Bool? = nil, allowedCallers: JSONValue? = nil, outputSchema: JSONValue? = nil) {
        self.deferLoading = deferLoading
        self.namespace = namespace
        self.async = async
        self.allowedCallers = allowedCallers
        self.outputSchema = outputSchema
    }
}

private func parseOpenAIToolOptions(_ providerOptions: SharedV4ProviderOptions?) -> OpenAIToolOptions {
    guard let raw = providerOptions?["openai"] else {
        return OpenAIToolOptions()
    }

    let deferLoading: Bool?
    if case .bool(let value)? = raw["deferLoading"] {
        deferLoading = value
    } else {
        deferLoading = nil
    }

    let namespace: OpenAIToolOptions.Namespace?
    if case .object(let object)? = raw["namespace"],
       case .string(let name)? = object["name"],
       case .string(let description)? = object["description"] {
        namespace = .init(name: name, description: description)
    } else {
        namespace = nil
    }

    return OpenAIToolOptions(
        deferLoading: deferLoading, namespace: namespace,
        async: { if case .bool(let value)? = raw["async"] { return value }; return nil }(),
        allowedCallers: raw["allowedCallers"].flatMap { $0 == .null ? nil : $0 },
        outputSchema: raw["outputSchema"].flatMap { $0 == .null ? nil : $0 }
    )
}

private func makeUserLocationJSON(_ location: OpenAIWebSearchArgs.UserLocation) -> JSONValue {
    var payload: [String: JSONValue] = [
        "type": .string("approximate")
    ]
    if let country = location.country {
        payload["country"] = .string(country)
    }
    if let city = location.city {
        payload["city"] = .string(city)
    }
    if let region = location.region {
        payload["region"] = .string(region)
    }
    if let timezone = location.timezone {
        payload["timezone"] = .string(timezone)
    }
    return .object(payload)
}

private func mapShellEnvironment(_ environment: [String: JSONValue]) throws -> JSONValue {
    let type = environment["type"]?.stringValue ?? "local"

    if type == "containerReference" {
        var payload: [String: JSONValue] = [
            "type": .string("container_reference")
        ]
        if let containerId = environment["containerId"] {
            payload["container_id"] = containerId
        }
        return .object(payload)
    }

    if type == "containerAuto" {
        var payload: [String: JSONValue] = [
            "type": .string("container_auto")
        ]
        if let fileIds = environment["fileIds"] {
            payload["file_ids"] = fileIds
        }
        if let memoryLimit = environment["memoryLimit"] {
            payload["memory_limit"] = memoryLimit
        }
        if let networkPolicy = environment["networkPolicy"] {
            payload["network_policy"] = mapShellNetworkPolicy(networkPolicy)
        }
        if let skills = environment["skills"] {
            payload["skills"] = try mapShellSkills(skills)
        }
        return .object(payload)
    }

    var payload: [String: JSONValue] = [
        "type": .string("local")
    ]
    if let skills = environment["skills"] {
        payload["skills"] = skills
    }
    return .object(payload)
}

private func mapShellNetworkPolicy(_ policy: JSONValue) -> JSONValue {
    guard case .object(let object) = policy,
          let type = object["type"]?.stringValue else {
        return policy
    }

    switch type {
    case "disabled":
        return .object(["type": .string("disabled")])
    case "allowlist":
        var payload: [String: JSONValue] = [
            "type": .string("allowlist")
        ]
        if let allowedDomains = object["allowedDomains"] {
            payload["allowed_domains"] = allowedDomains
        }
        if let domainSecrets = object["domainSecrets"] {
            payload["domain_secrets"] = domainSecrets
        }
        return .object(payload)
    default:
        return policy
    }
}

private func mapShellSkills(_ skillsValue: JSONValue) throws -> JSONValue {
    guard case .array(let skills) = skillsValue else {
        return skillsValue
    }

    let mapped: [JSONValue] = try skills.map { skill in
        guard case .object(let object) = skill,
              let type = object["type"]?.stringValue else {
            return skill
        }

        switch type {
        case "skillReference":
            guard case .object(let referenceObject)? = object["providerReference"] else {
                return skill
            }
            let reference = Dictionary(uniqueKeysWithValues: referenceObject.compactMap { key, value -> (String, String)? in
                guard case .string(let providerId) = value else {
                    return nil
                }
                return (key, providerId)
            })
            var payload: [String: JSONValue] = [
                "type": .string("skill_reference"),
                "skill_id": .string(try resolveProviderReference(reference: reference, provider: "openai")),
                "version": .string("latest")
            ]
            if let version = object["version"] {
                payload["version"] = version
            }
            return .object(payload)

        case "inline":
            var payload: [String: JSONValue] = [
                "type": .string("inline")
            ]
            if let name = object["name"] {
                payload["name"] = name
            }
            if let description = object["description"] {
                payload["description"] = description
            }
            if let source = object["source"], case .object(let sourceObject) = source {
                var sourcePayload: [String: JSONValue] = [:]
                if let sourceType = sourceObject["type"] {
                    sourcePayload["type"] = sourceType
                }
                if let mediaType = sourceObject["mediaType"] {
                    sourcePayload["media_type"] = mediaType
                }
                if let data = sourceObject["data"] {
                    sourcePayload["data"] = data
                }
                payload["source"] = .object(sourcePayload)
            }
            return .object(payload)

        default:
            return skill
        }
    }

    return .array(mapped)
}

private extension JSONValue {
    var stringValue: String? {
        if case .string(let value) = self {
            return value
        }
        return nil
    }
}

private func mapToolChoice(
    _ choice: LanguageModelV4ToolChoice?,
    toolNameMapping: ToolNameMapping,
    customProviderToolNames: Set<Data>
) throws -> JSONValue? {
    guard let choice else { return nil }

    switch choice {
    case .auto:
        return .string("auto")
    case .none:
        return .string("none")
    case .required:
        return .string("required")
    case .tool(let toolName):
        let resolvedToolName = toolNameMapping.toProviderToolName(toolName)
        if ["code_interpreter", "file_search", "image_generation", "web_search_preview", "web_search", "mcp", "apply_patch", "computer", "programmatic_tool_calling"].contains(resolvedToolName) {
            return .object(["type": .string(resolvedToolName)])
        }
        if customProviderToolNames.contains(Data(resolvedToolName.utf8)) {
            return .object([
                "type": .string("custom"),
                "name": .string(resolvedToolName)
            ])
        }
        return .object([
            "type": .string("function"),
            "name": .string(resolvedToolName)
        ])
    }
}
