import Foundation
import AISDKProvider
import AISDKProviderUtils

struct OpenAIResponsesPreparedTools: Sendable {
    let tools: [JSONValue]?
    let toolChoice: JSONValue?
    let warnings: [SharedV3Warning]
}

func prepareOpenAIResponsesTools(
    tools: [LanguageModelV3Tool]?,
    toolChoice: LanguageModelV3ToolChoice?,
    allowedTools: OpenAIResponsesAllowedTools? = nil,
    toolNameMapping: OpenAIToolNameMapping = .init(),
    customProviderToolNames: Set<String> = []
) async throws -> OpenAIResponsesPreparedTools {
    guard let tools, !tools.isEmpty else {
        return OpenAIResponsesPreparedTools(tools: nil, toolChoice: nil, warnings: [])
    }

    let warnings: [SharedV3Warning] = []
    var openAITools: [JSONValue] = []
    var namespaceTools: [String: (description: String, index: Int)] = [:]
    var resolvedCustomProviderToolNames = customProviderToolNames

    for tool in tools {
        switch tool {
        case .function(let functionTool):
            let openAIOptions = parseOpenAIFunctionToolOptions(functionTool.providerOptions)
            var payload: [String: JSONValue] = [
                "type": .string("function"),
                "name": .string(functionTool.name),
                "parameters": functionTool.inputSchema
            ]
            if let description = functionTool.description {
                payload["description"] = .string(description)
            }
            if let strict = functionTool.strict {
                payload["strict"] = .bool(strict)
            }
            if let deferLoading = openAIOptions.deferLoading {
                payload["defer_loading"] = .bool(deferLoading)
            }

            if let namespace = openAIOptions.namespace {
                if let existing = namespaceTools[namespace.name] {
                    guard existing.description == namespace.description else {
                        throw UnsupportedFunctionalityError(functionality: "conflicting descriptions for OpenAI tool namespace \"\(namespace.name)\"")
                    }
                    guard case .object(var namespaceObject) = openAITools[existing.index],
                          case .array(var namespaceFunctionTools)? = namespaceObject["tools"] else {
                        throw UnsupportedFunctionalityError(functionality: "invalid OpenAI tool namespace state")
                    }
                    namespaceFunctionTools.append(.object(payload))
                    namespaceObject["tools"] = .array(namespaceFunctionTools)
                    openAITools[existing.index] = .object(namespaceObject)
                } else {
                    let index = openAITools.count
                    namespaceTools[namespace.name] = (namespace.description, index)
                    openAITools.append(.object([
                        "type": .string("namespace"),
                        "name": .string(namespace.name),
                        "description": .string(namespace.description),
                        "tools": .array([.object(payload)])
                    ]))
                }
            } else {
                openAITools.append(.object(payload))
            }

        case .provider(let providerTool):
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
                    rankingOptions = rankingPayload.isEmpty ? nil : .object(rankingPayload)
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
                    if !filtersPayload.isEmpty {
                        payload["filters"] = .object(filtersPayload)
                    }
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
                resolvedCustomProviderToolNames.insert(providerTool.name)

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
        }
    }

    let finalTools = openAITools
    let finalToolChoice: JSONValue?
    if let allowedTools {
        finalToolChoice = .object([
            "type": .string("allowed_tools"),
            "mode": .string(allowedTools.mode ?? "auto"),
            "tools": .array(allowedTools.toolNames.map { name in
                .object([
                    "type": .string("function"),
                    "name": .string(toolNameMapping.toProviderToolName(name))
                ])
            })
        ])
    } else {
        finalToolChoice = try mapToolChoice(
            toolChoice,
            toolNameMapping: toolNameMapping,
            customProviderToolNames: resolvedCustomProviderToolNames
        )
    }

    return OpenAIResponsesPreparedTools(tools: finalTools, toolChoice: finalToolChoice, warnings: warnings)
}

private struct OpenAIFunctionToolOptions {
    struct Namespace {
        let name: String
        let description: String
    }

    var deferLoading: Bool?
    var namespace: Namespace?
}

private func parseOpenAIFunctionToolOptions(_ providerOptions: SharedV3ProviderOptions?) -> OpenAIFunctionToolOptions {
    guard let raw = providerOptions?["openai"] else {
        return OpenAIFunctionToolOptions()
    }

    let deferLoading: Bool?
    if case .bool(let value)? = raw["deferLoading"] {
        deferLoading = value
    } else {
        deferLoading = nil
    }

    let namespace: OpenAIFunctionToolOptions.Namespace?
    if case .object(let object)? = raw["namespace"],
       case .string(let name)? = object["name"],
       case .string(let description)? = object["description"] {
        namespace = .init(name: name, description: description)
    } else {
        namespace = nil
    }

    return OpenAIFunctionToolOptions(deferLoading: deferLoading, namespace: namespace)
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
    _ choice: LanguageModelV3ToolChoice?,
    toolNameMapping: OpenAIToolNameMapping,
    customProviderToolNames: Set<String>
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
        if ["code_interpreter", "file_search", "image_generation", "web_search_preview", "web_search", "mcp", "apply_patch"].contains(resolvedToolName) {
            return .object(["type": .string(resolvedToolName)])
        }
        if customProviderToolNames.contains(resolvedToolName) {
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
