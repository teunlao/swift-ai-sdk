/**
 Option handling and reference tracking for Zod v3 JSON Schema conversion.

 Port of `@ai-sdk/provider-utils/src/to-json-schema/zod3-to-json-schema/options.ts`
 and `refs.ts`.
 */
import Foundation
import AISDKProvider

// MARK: - JSON Schema Helpers

typealias JsonSchemaObject = [String: JSONValue]

// MARK: - Override Handling

enum OverrideResult {
    case useDefault
    case schema(JsonSchemaObject?)
}

typealias OverrideCallback = @Sendable (
    _ def: ZodTypeDef,
    _ refs: Refs,
    _ seen: Seen?,
    _ forceResolution: Bool
) -> OverrideResult

typealias PostProcessCallback = @Sendable (
    _ jsonSchema: JsonSchemaObject?,
    _ def: ZodTypeDef,
    _ refs: Refs
) -> JsonSchemaObject?

// MARK: - Options Definitions

enum DateStrategy: Sendable {
    case formatDateTime
    case formatDate
    case string
    case integer
}

enum MapStrategy: Sendable {
    case entries
    case record
}

enum RemoveAdditionalStrategy: Sendable {
    case passthrough
    case strict
}

enum RefStrategy: Sendable {
    case root
    case relative
    case none
    case seen
}

enum EffectStrategy: Sendable {
    case input
    case any
}

enum PipeStrategy: Sendable {
    case input
    case output
    case all
}

enum PatternStrategy: Sendable {
    case escape
    case preserve
}

enum EmailStrategy: Sendable {
    case formatEmail
    case formatIdnEmail
    case patternZod
}

enum Base64Strategy: Sendable {
    case formatBinary
    case contentEncodingBase64
    case patternZod
}

enum NameStrategy: Sendable {
    case ref
    case title
}

struct Options: Sendable {
    var name: String?
    var refStrategy: RefStrategy
    var basePath: [String]
    var effectStrategy: EffectStrategy
    var pipeStrategy: PipeStrategy
    var dateStrategy: DateStrategySetting
    var mapStrategy: MapStrategy
    var removeAdditionalStrategy: RemoveAdditionalStrategy
    var allowedAdditionalProperties: Bool?
    var rejectedAdditionalProperties: Bool?
    var strictUnions: Bool
    var definitionPath: String
    var definitions: [String: ZodSchema]
    var errorMessages: Bool
    var patternStrategy: PatternStrategy
    var applyRegexFlags: Bool
    var emailStrategy: EmailStrategy
    var base64Strategy: Base64Strategy
    var nameStrategy: NameStrategy
    var override: OverrideCallback?
    var postProcess: PostProcessCallback?
}

enum DateStrategySetting: Sendable {
    case single(DateStrategy)
    case multiple([DateStrategy])

    var values: [DateStrategy] {
        switch self {
        case .single(let value):
            return [value]
        case .multiple(let values):
            return values
        }
    }
}

extension DateStrategySetting {
    static func from(_ strategies: [DateStrategy]) -> DateStrategySetting {
        strategies.count == 1 ? .single(strategies[0]) : .multiple(strategies)
    }
}

let defaultOptions = Options(
    name: nil,
    refStrategy: .root,
    basePath: ["#"],
    effectStrategy: .input,
    pipeStrategy: .all,
    dateStrategy: .single(.formatDateTime),
    mapStrategy: .entries,
    removeAdditionalStrategy: .passthrough,
    allowedAdditionalProperties: true,
    rejectedAdditionalProperties: false,
    strictUnions: false,
    definitionPath: "definitions",
    definitions: [:],
    errorMessages: false,
    patternStrategy: .escape,
    applyRegexFlags: false,
    emailStrategy: .formatEmail,
    base64Strategy: .contentEncodingBase64,
    nameStrategy: .ref,
    override: nil,
    postProcess: nil
)

func getDefaultOptions(_ options: PartialOptions?) -> Options {
    guard let options else {
        return defaultOptions
    }

    var resolved = defaultOptions

    if let name = options.name {
        resolved.name = name
    }

    if let refStrategy = options.refStrategy {
        resolved.refStrategy = refStrategy
    }

    if let basePath = options.basePath {
        resolved.basePath = basePath
    }

    if let effectStrategy = options.effectStrategy {
        resolved.effectStrategy = effectStrategy
    }

    if let pipeStrategy = options.pipeStrategy {
        resolved.pipeStrategy = pipeStrategy
    }

    if let dateStrategy = options.dateStrategy {
        switch dateStrategy {
        case .single(let value):
            resolved.dateStrategy = .single(value)
        case .multiple(let values):
            resolved.dateStrategy = .multiple(values)
        }
    }

    if let mapStrategy = options.mapStrategy {
        resolved.mapStrategy = mapStrategy
    }

    if let removeStrategy = options.removeAdditionalStrategy {
        resolved.removeAdditionalStrategy = removeStrategy
    }

    if let allowed = options.allowedAdditionalProperties {
        resolved.allowedAdditionalProperties = allowed
    }

    if let rejected = options.rejectedAdditionalProperties {
        resolved.rejectedAdditionalProperties = rejected
    }

    if let strictUnions = options.strictUnions {
        resolved.strictUnions = strictUnions
    }

    if let definitionPath = options.definitionPath {
        resolved.definitionPath = definitionPath
    }

    if let definitions = options.definitions {
        resolved.definitions = definitions
    }

    if let errorMessages = options.errorMessages {
        resolved.errorMessages = errorMessages
    }

    if let patternStrategy = options.patternStrategy {
        resolved.patternStrategy = patternStrategy
    }

    if let applyRegexFlags = options.applyRegexFlags {
        resolved.applyRegexFlags = applyRegexFlags
    }

    if let emailStrategy = options.emailStrategy {
        resolved.emailStrategy = emailStrategy
    }

    if let base64Strategy = options.base64Strategy {
        resolved.base64Strategy = base64Strategy
    }

    if let nameStrategy = options.nameStrategy {
        resolved.nameStrategy = nameStrategy
    }

    if let override = options.override {
        resolved.override = override
    }

    if let postProcess = options.postProcess {
        resolved.postProcess = postProcess
    }

    return resolved
}

struct PartialOptions: Sendable {
    var name: String?
    var refStrategy: RefStrategy?
    var basePath: [String]?
    var effectStrategy: EffectStrategy?
    var pipeStrategy: PipeStrategy?
    var dateStrategy: DateStrategySetting?
    var mapStrategy: MapStrategy?
    var removeAdditionalStrategy: RemoveAdditionalStrategy?
    var allowedAdditionalProperties: Bool?
    var rejectedAdditionalProperties: Bool?
    var strictUnions: Bool?
    var definitionPath: String?
    var definitions: [String: ZodSchema]?
    var errorMessages: Bool?
    var patternStrategy: PatternStrategy?
    var applyRegexFlags: Bool?
    var emailStrategy: EmailStrategy?
    var base64Strategy: Base64Strategy?
    var nameStrategy: NameStrategy?
    var override: OverrideCallback?
    var postProcess: PostProcessCallback?
}

// MARK: - Refs

struct Seen: Sendable {
    let def: ZodTypeDef
    var path: [String]
    var jsonSchema: JsonSchemaObject?
}

final class SeenRegistry: @unchecked Sendable {
    private var storage: [ObjectIdentifier: Seen]

    init(initial: [ObjectIdentifier: Seen] = [:]) {
        self.storage = initial
    }

    subscript(def: ZodTypeDef) -> Seen? {
        get { storage[ObjectIdentifier(def)] }
        set { storage[ObjectIdentifier(def)] = newValue }
    }
}

struct Refs: Sendable {
    let options: Options
    var currentPath: [String]
    var propertyPath: [String]?
    let seenRegistry: SeenRegistry

    init(options: Options, currentPath: [String], propertyPath: [String]? = nil, seenRegistry: SeenRegistry) {
        self.options = options
        self.currentPath = currentPath
        self.propertyPath = propertyPath
        self.seenRegistry = seenRegistry
    }

    var refStrategy: RefStrategy { options.refStrategy }
    var basePath: [String] { options.basePath }
    var definitionPath: String { options.definitionPath }
    var effectStrategy: EffectStrategy { options.effectStrategy }
    var pipeStrategy: PipeStrategy { options.pipeStrategy }
    var allowedAdditionalProperties: Bool? { options.allowedAdditionalProperties }
    var rejectedAdditionalProperties: Bool? { options.rejectedAdditionalProperties }
    var removeAdditionalStrategy: RemoveAdditionalStrategy { options.removeAdditionalStrategy }
    var strictUnions: Bool { options.strictUnions }
    var errorMessages: Bool { options.errorMessages }
    var patternStrategy: PatternStrategy { options.patternStrategy }
    var applyRegexFlags: Bool { options.applyRegexFlags }
    var emailStrategy: EmailStrategy { options.emailStrategy }
    var base64Strategy: Base64Strategy { options.base64Strategy }
    var mapStrategy: MapStrategy { options.mapStrategy }
    var nameStrategy: NameStrategy { options.nameStrategy }
    var override: OverrideCallback? { options.override }
    var postProcess: PostProcessCallback? { options.postProcess }
    var dateStrategy: DateStrategySetting { options.dateStrategy }
    var definitions: [String: ZodSchema] { options.definitions }

    subscript(def: ZodTypeDef) -> Seen? {
        get { seenRegistry[def] }
        set { seenRegistry[def] = newValue }
    }

    func with(currentPath: [String]? = nil, propertyPath: [String]? = nil) -> Refs {
        Refs(
            options: options,
            currentPath: currentPath ?? self.currentPath,
            propertyPath: propertyPath ?? self.propertyPath,
            seenRegistry: seenRegistry
        )
    }
}

func getRefs(_ options: Zod3Options?) -> Refs {
    let resolvedOptions: Options

    switch options {
    case .name(let name):
        resolvedOptions = getDefaultOptions(PartialOptions(name: name))
    case .partial(let partial):
        resolvedOptions = getDefaultOptions(partial)
    case .none:
        resolvedOptions = defaultOptions
    }

    let basePath: [String]
    if let name = resolvedOptions.name {
        basePath = resolvedOptions.basePath + [resolvedOptions.definitionPath, name]
    } else {
        basePath = resolvedOptions.basePath
    }

    let registry = SeenRegistry(
        initial: resolvedOptions.definitions.reduce(into: [:]) { acc, element in
            let identifier = ObjectIdentifier(element.value._def)
            acc[identifier] = Seen(
                def: element.value._def,
                path: resolvedOptions.basePath + [resolvedOptions.definitionPath, element.key],
                jsonSchema: nil
            )
        }
    )

    return Refs(
        options: resolvedOptions,
        currentPath: basePath,
        propertyPath: nil,
        seenRegistry: registry
    )
}

enum Zod3Options: Sendable {
    case name(String)
    case partial(PartialOptions)
}

// MARK: - Post Processing Helpers

let jsonDescription: PostProcessCallback = { jsonSchema, def, _ in
    guard
        let description = def.description,
        let data = description.data(using: .utf8),
        let parsed = try? JSONSerialization.jsonObject(with: data),
        let object = parsed as? [String: Any],
        var schema = jsonSchema
    else {
        return jsonSchema
    }

    for (key, value) in object {
        if let jsonValue = try? jsonValue(from: value) {
            schema[key] = jsonValue
        }
    }

    return schema
}
