import Foundation
import AISDKProvider

// MARK: - Schema Validation Result

public struct AnySendable: @unchecked Sendable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }
}

public enum SchemaValidationResult<Output>: @unchecked Sendable {
    case success(value: Output)
    case failure(error: TypeValidationError)

    public var value: Output? {
        if case .success(let value) = self {
            return value
        }
        return nil
    }

    public var error: TypeValidationError? {
        if case .failure(let error) = self {
            return error
        }
        return nil
    }
}

// MARK: - Schema Core

public struct Schema<Output>: @unchecked Sendable {
    public typealias JSONSchemaResolver = @Sendable () async throws -> JSONValue
    public typealias Validator = @Sendable (_ value: Any) async throws -> SchemaValidationResult<Output>

    private let storage: SchemaStorage<Output>

    public init(jsonSchemaResolver: @escaping JSONSchemaResolver, validator: Validator?) {
        self.storage = SchemaStorage(jsonSchemaResolver: jsonSchemaResolver, validator: validator)
    }

    public func jsonSchema() async throws -> JSONValue {
        try await storage.jsonSchema()
    }

    public func validate(_ value: Any) async -> SchemaValidationResult<Output> {
        await storage.validate(AnySendable(value))
    }
}

private actor SchemaStorage<Output> {
    private let jsonSchemaResolver: Schema<Output>.JSONSchemaResolver
    private var cachedJSONSchema: JSONValue?
    private let validator: Schema<Output>.Validator?

    init(jsonSchemaResolver: @escaping Schema<Output>.JSONSchemaResolver, validator: Schema<Output>.Validator?) {
        self.jsonSchemaResolver = jsonSchemaResolver
        self.validator = validator
    }

    func jsonSchema() async throws -> JSONValue {
        if let cachedJSONSchema {
            return cachedJSONSchema
        }

        let schema = try await jsonSchemaResolver()
        cachedJSONSchema = schema
        return schema
    }

    func validate(_ sendableValue: AnySendable) async -> SchemaValidationResult<Output> {
        let value = sendableValue.value

        guard let validator else {
            return SchemaValidationResult.passthrough(value, as: Output.self)
        }

        do {
            return try await validator(value)
        } catch let error as TypeValidationError {
            return .failure(error: error)
        } catch {
            let wrapped = TypeValidationError.wrap(value: value, cause: error)
            return .failure(error: wrapped)
        }
    }
}

private extension SchemaValidationResult {
    static func passthrough(_ value: Any, as type: Output.Type) -> SchemaValidationResult<Output> {
        if let typed = value as? Output {
            return .success(value: typed)
        }

        if Output.self == JSONValue.self {
            // Port of `@ai-sdk/provider-utils/src/schema.ts` passthrough behavior.
            // TypeScript's Zod schemas convert raw JSON objects into the typed output even
            // when no explicit validator is provided. Perform the same conversion here
            // so JSONValue schemas accept dictionaries parsed from JSON text.
            do {
                let converted = try jsonValue(from: value)
                if let typed = converted as? Output {
                    return .success(value: typed)
                }
            } catch {
                let wrapped = TypeValidationError.wrap(value: value, cause: error)
                return .failure(error: wrapped)
            }
        }

        let mismatch = SchemaTypeMismatchError(expected: type, actual: value)
        let error = TypeValidationError.wrap(value: value, cause: mismatch)
        return .failure(error: error)
    }
}

// MARK: - JSON Schema Builders

/// Specialized overload for JSONValue schemas with automatic validation.
///
/// When creating a schema for JSONValue output, this overload automatically
/// provides a validator that converts parsed JSON ([String: Any], etc.) to JSONValue.
/// This matches TypeScript behavior where Zod schemas always include validation.
///
/// Port of upstream behavior: TypeScript's Zod schemas include validation that transforms
/// raw parsed values to typed outputs. Swift needs explicit conversion from [String: Any] to JSONValue.
///
/// Port of `@ai-sdk/provider-utils/src/schema.ts` - validation behavior.
public func jsonSchema(
    _ jsonSchema: JSONValue
) -> Schema<JSONValue> {
    Schema(
        jsonSchemaResolver: { jsonSchema },
        validator: { value in
            do {
                // Reuse existing conversion logic from ParseJSON.swift
                let converted = try jsonValue(from: value)
                let issues = JSONSchemaValidator(schema: jsonSchema).validate(value: converted)

                if issues.isEmpty {
                    return .success(value: converted)
                }

                let validationError = JSONSchemaValidationIssuesError(issues: issues)
                let wrapped = TypeValidationError.wrap(value: value, cause: validationError)
                return .failure(error: wrapped)
            } catch {
                let wrapped = TypeValidationError.wrap(value: value, cause: error)
                return .failure(error: wrapped)
            }
        }
    )
}

/// Generic overload for typed schemas with optional custom validation.
///
/// This overload is for cases where you want a typed schema (not JSONValue)
/// with optional custom validation logic.
public func jsonSchema<Output>(
    _ jsonSchema: JSONValue,
    validate: Schema<Output>.Validator?
) -> Schema<Output> {
    return Schema(jsonSchemaResolver: { jsonSchema }, validator: validate)
}

public func jsonSchema<Output>(
    _ jsonSchema: @escaping @Sendable () -> JSONValue,
    validate: Schema<Output>.Validator? = nil
) -> Schema<Output> {
    Schema(jsonSchemaResolver: { jsonSchema() }, validator: validate)
}

public func jsonSchema<Output>(
    _ jsonSchema: @escaping @Sendable () async throws -> JSONValue,
    validate: Schema<Output>.Validator? = nil
) -> Schema<Output> {
    Schema(jsonSchemaResolver: jsonSchema, validator: validate)
}

public struct SchemaJSONSerializationError: Error, CustomStringConvertible, Sendable {
    public let value: AnySendable

    public init(value: Any) {
        self.value = AnySendable(value)
    }

    public var description: String {
        "Value cannot be serialized to JSON for validation: \(String(describing: value.value))"
    }
}

public extension Schema where Output: Decodable & Sendable {
    static func codable(
        _ type: Output.Type,
        jsonSchema: JSONValue,
        configureDecoder: (@Sendable (JSONDecoder) -> JSONDecoder)? = nil
    ) -> Schema<Output> {
        Schema(jsonSchemaResolver: { jsonSchema }) { value in
            guard JSONSerialization.isValidJSONObject(value) else {
                let serializationError = SchemaJSONSerializationError(value: value)
                return .failure(
                    error: TypeValidationError.wrap(value: value, cause: serializationError)
                )
            }

            do {
                let data = try JSONSerialization.data(withJSONObject: value, options: [])
                let decoder = configureDecoder?(JSONDecoder()) ?? JSONDecoder()
                let decoded = try decoder.decode(Output.self, from: data)
                return .success(value: decoded)
            } catch {
                let wrapped = TypeValidationError.wrap(value: value, cause: error)
                return .failure(error: wrapped)
            }
        }
    }
}

// MARK: - Lazy Schema

public struct LazySchema<Output>: @unchecked Sendable {
    private final class Storage: @unchecked Sendable {
        private let loader: @Sendable () -> Schema<Output>
        private var cached: Schema<Output>?
        private let lock = NSLock()

        init(loader: @escaping @Sendable () -> Schema<Output>) {
            self.loader = loader
        }

        func resolve() -> Schema<Output> {
            lock.lock()
            defer { lock.unlock() }

            if let cached {
                return cached
            }

            let schema = loader()
            cached = schema
            return schema
        }
    }

    private let storage: Storage

    public init(_ loader: @escaping @Sendable () -> Schema<Output>) {
        self.storage = Storage(loader: loader)
    }

    public func callAsFunction() -> Schema<Output> {
        storage.resolve()
    }
}

@inlinable
public func lazySchema<Output>(
    _ loader: @escaping @Sendable () -> Schema<Output>
) -> LazySchema<Output> {
    LazySchema(loader)
}

// MARK: - Standard Schema Integration

public enum StandardSchemaValidationResult<Output>: @unchecked Sendable {
    case value(Output)
    case issues(Any)
}

public struct StandardSchemaV1<Output>: @unchecked Sendable {
    public struct Definition: Sendable {
        public let version: Int
        public let vendor: String
        public let annotations: [String: JSONValue]?
        public let jsonSchema: (@Sendable () async throws -> JSONValue)?
        public let validate: @Sendable (Any) async throws -> StandardSchemaValidationResult<Output>

        public init(
            version: Int = 1,
            vendor: String,
            annotations: [String: JSONValue]? = nil,
            jsonSchema: (@Sendable () async throws -> JSONValue)? = nil,
            validate: @escaping @Sendable (Any) async throws -> StandardSchemaValidationResult<Output>
        ) {
            self.version = version
            self.vendor = vendor
            self.annotations = annotations
            self.jsonSchema = jsonSchema
            self.validate = validate
        }
    }

    public let definition: Definition

    public init(definition: Definition) {
        self.definition = definition
    }
}

public struct UnsupportedStandardSchemaVendorError: Error, CustomStringConvertible, Sendable {
    public let vendor: String

    public init(vendor: String) {
        self.vendor = vendor
    }

    public var description: String {
        "Unsupported standard schema vendor: \(vendor)"
    }
}

public struct SchemaValidationIssuesError: Error, CustomStringConvertible, @unchecked Sendable {
    public let vendor: String
    public let issues: Any

    public init(vendor: String, issues: Any) {
        self.vendor = vendor
        self.issues = issues
    }

    public var description: String {
        "Schema validation issues from vendor '\(vendor)': \(String(describing: issues))"
    }
}

public func standardSchema<Output>(_ schema: StandardSchemaV1<Output>) -> Schema<Output> {
    let vendor = schema.definition.vendor

    if vendor == "zod" {
        let resolver: Schema<Output>.JSONSchemaResolver = {
            throw UnsupportedStandardSchemaVendorError(vendor: vendor)
        }

        let validator: Schema<Output>.Validator = { value in
            let error = TypeValidationError.wrap(
                value: value,
                cause: UnsupportedStandardSchemaVendorError(vendor: vendor)
            )
            return .failure(error: error)
        }

        return Schema(jsonSchemaResolver: resolver, validator: validator)
    }

    let resolver: Schema<Output>.JSONSchemaResolver = {
        if let jsonSchema = schema.definition.jsonSchema {
            return try await jsonSchema()
        }

        return .object([
            "properties": .object([:]),
            "additionalProperties": .bool(false)
        ])
    }

    let validator: Schema<Output>.Validator = { value in
        do {
            let result = try await schema.definition.validate(value)
            switch result {
            case .value(let output):
                return .success(value: output)
            case .issues(let issues):
                let error = TypeValidationError.wrap(
                    value: value,
                    cause: SchemaValidationIssuesError(vendor: vendor, issues: issues)
                )
                return .failure(error: error)
            }
        } catch let error as TypeValidationError {
            return .failure(error: error)
        } catch {
            let wrapped = TypeValidationError.wrap(value: value, cause: error)
            return .failure(error: wrapped)
        }
    }

    return Schema(jsonSchemaResolver: resolver, validator: validator)
}

// MARK: - Flexible Schema Wrapper

public struct FlexibleSchema<Output>: @unchecked Sendable {
    private let resolver: @Sendable () -> Schema<Output>

    public init(_ schema: Schema<Output>) {
        self.resolver = { schema }
    }

    public init(_ schema: LazySchema<Output>) {
        self.resolver = { schema() }
    }

    public init(_ schema: StandardSchemaV1<Output>) {
        self.resolver = { standardSchema(schema) }
    }

    public func resolve() -> Schema<Output> {
        resolver()
    }
}

public func asSchema<Output>(_ schema: FlexibleSchema<Output>?) -> Schema<Output> {
    guard let schema else {
        return jsonSchema(
            .object([
                "properties": .object([:]),
                "additionalProperties": .bool(false)
            ]),
            validate: nil
        )
    }

    return schema.resolve()
}

// MARK: - Helper Errors

struct SchemaTypeMismatchError: Error, CustomStringConvertible, @unchecked Sendable {
    let expected: Any.Type
    let actual: Any

    var description: String {
        "Expected value of type \(expected) but received \(String(describing: actual))"
    }
}

// MARK: - Zod Compatibility Shims

public struct ZodSchemaOptions: Sendable {
    public let useReferences: Bool

    public init(useReferences: Bool = false) {
        self.useReferences = useReferences
    }
}

public func zodSchema<Output>(
    _ schema: Any,
    options: ZodSchemaOptions = ZodSchemaOptions()
) -> Schema<Output> {
    _ = schema
    _ = options

    let definition = StandardSchemaV1<Output>.Definition(
        vendor: "zod",
        validate: { _ in
            .issues(UnsupportedStandardSchemaVendorError(vendor: "zod"))
        }
    )

    return standardSchema(StandardSchemaV1(definition: definition))
}

public func zod3Schema<Output>(
    _ schema: Any,
    options: ZodSchemaOptions = ZodSchemaOptions()
) -> Schema<Output> {
    zodSchema(schema, options: options)
}

public func zod4Schema<Output>(
    _ schema: Any,
    options: ZodSchemaOptions = ZodSchemaOptions()
) -> Schema<Output> {
    zodSchema(schema, options: options)
}

public func isZod4Schema(_ schema: Any) -> Bool {
    _ = schema
    return false
}
