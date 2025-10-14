/**
 Core type definitions and helpers for converting Zod v3 schemas to JSON Schema.

 Port of `@ai-sdk/provider-utils/src/to-json-schema/zod3-to-json-schema`.
 */
import Foundation
import AISDKProvider

// MARK: - Zod Core Types

enum ZodFirstPartyTypeKind: String, Sendable {
    case zodString = "ZodString"
    case zodNumber = "ZodNumber"
    case zodObject = "ZodObject"
    case zodBigInt = "ZodBigInt"
    case zodBoolean = "ZodBoolean"
    case zodDate = "ZodDate"
    case zodUndefined = "ZodUndefined"
    case zodNull = "ZodNull"
    case zodArray = "ZodArray"
    case zodUnion = "ZodUnion"
    case zodDiscriminatedUnion = "ZodDiscriminatedUnion"
    case zodIntersection = "ZodIntersection"
    case zodTuple = "ZodTuple"
    case zodRecord = "ZodRecord"
    case zodLiteral = "ZodLiteral"
    case zodEnum = "ZodEnum"
    case zodNativeEnum = "ZodNativeEnum"
    case zodNullable = "ZodNullable"
    case zodOptional = "ZodOptional"
    case zodMap = "ZodMap"
    case zodSet = "ZodSet"
    case zodPromise = "ZodPromise"
    case zodEffects = "ZodEffects"
    case zodAny = "ZodAny"
    case zodUnknown = "ZodUnknown"
    case zodDefault = "ZodDefault"
    case zodBranded = "ZodBranded"
    case zodReadonly = "ZodReadonly"
    case zodCatch = "ZodCatch"
    case zodNever = "ZodNever"
    case zodLazy = "ZodLazy"
    case zodPipeline = "ZodPipeline"
    case zodFunction = "ZodFunction"
    case zodVoid = "ZodVoid"
    case zodSymbol = "ZodSymbol"
    case zodNaN = "ZodNaN"
}

class ZodTypeDef: @unchecked Sendable {
    let typeName: ZodFirstPartyTypeKind
    var description: String?

    init(typeName: ZodFirstPartyTypeKind, description: String? = nil) {
        self.typeName = typeName
        self.description = description
    }
}

final class ZodSchema: @unchecked Sendable {
    let _def: ZodTypeDef

    init(_ def: ZodTypeDef) {
        self._def = def
    }

    func isOptional() -> Bool {
        switch _def {
        case _ as ZodOptionalDef:
            return true
        case let defaultDef as ZodDefaultDef:
            return defaultDef.innerType.isOptional()
        case let catchDef as ZodCatchDef:
            return catchDef.innerType.isOptional()
        default:
            return false
        }
    }
}

extension ZodSchema {
    static func any() -> ZodSchema {
        ZodSchema(ZodAnyDef())
    }
}

// MARK: - Helper Structures

struct ZodNumericBound<T: Comparable & Sendable>: Sendable {
    let value: T
    let inclusive: Bool
}

enum ZodNumberCheck: Sendable {
    case min(ZodNumericBound<Double>)
    case max(ZodNumericBound<Double>)
    case multipleOf(Double)
    case int
}

enum ZodBigIntCheck: Sendable {
    case min(ZodNumericBound<Int>)
    case max(ZodNumericBound<Int>)
    case multipleOf(Int)
}

enum ZodDateCheck: Sendable {
    case min(Double)
    case max(Double)
}

struct ZodArraySizeCheck: Sendable {
    let value: Int
}

struct ZodSetSizeCheck: Sendable {
    let value: Int
}

struct ZodRegexPattern: Sendable {
    let pattern: String
    let flags: String

    init(pattern: String, flags: String = "") {
        self.pattern = pattern
        self.flags = flags
    }
}

enum ZodIPVersion: Sendable {
    case v4
    case v6
    case v4AndV6

    init(version: String?) {
        switch version {
        case "v4": self = .v4
        case "v6": self = .v6
        default: self = .v4AndV6
        }
    }
}

enum ZodStringCheck: Sendable {
    case min(value: Int, message: String?)
    case max(value: Int, message: String?)
    case length(value: Int, message: String?)
    case email(message: String?)
    case url(message: String?)
    case uuid(message: String?)
    case regex(pattern: ZodRegexPattern, message: String?)
    case cuid(message: String?)
    case cuid2(message: String?)
    case startsWith(value: String, message: String?)
    case endsWith(value: String, message: String?)
    case datetime(message: String?)
    case date(message: String?)
    case time(message: String?)
    case duration(message: String?)
    case includes(value: String, message: String?)
    case ip(version: ZodIPVersion, message: String?)
    case emoji(message: String?)
    case ulid(message: String?)
    case base64(message: String?)
    case base64url(message: String?)
    case jwt(message: String?)
    case cidr(version: ZodIPVersion, message: String?)
    case nanoid(message: String?)
    case toLowerCase
    case toUpperCase
    case trim
}

// MARK: - Zod Definition Implementations

final class ZodStringDef: ZodTypeDef {
    let checks: [ZodStringCheck]

    init(checks: [ZodStringCheck] = [], description: String? = nil) {
        self.checks = checks
        super.init(typeName: .zodString, description: description)
    }
}

final class ZodNumberDef: ZodTypeDef {
    let checks: [ZodNumberCheck]

    init(checks: [ZodNumberCheck] = [], description: String? = nil) {
        self.checks = checks
        super.init(typeName: .zodNumber, description: description)
    }
}

final class ZodBigIntDef: ZodTypeDef {
    let checks: [ZodBigIntCheck]

    init(checks: [ZodBigIntCheck] = [], description: String? = nil) {
        self.checks = checks
        super.init(typeName: .zodBigInt, description: description)
    }
}

final class ZodBooleanDef: ZodTypeDef {
    init(description: String? = nil) {
        super.init(typeName: .zodBoolean, description: description)
    }
}

final class ZodDateDef: ZodTypeDef {
    let checks: [ZodDateCheck]

    init(checks: [ZodDateCheck] = [], description: String? = nil) {
        self.checks = checks
        super.init(typeName: .zodDate, description: description)
    }
}

final class ZodUndefinedDef: ZodTypeDef {
    init(description: String? = nil) {
        super.init(typeName: .zodUndefined, description: description)
    }
}

final class ZodNullDef: ZodTypeDef {
    init(description: String? = nil) {
        super.init(typeName: .zodNull, description: description)
    }
}

final class ZodNeverDef: ZodTypeDef {
    init(description: String? = nil) {
        super.init(typeName: .zodNever, description: description)
    }
}

final class ZodNaNDef: ZodTypeDef {
    init(description: String? = nil) {
        super.init(typeName: .zodNaN, description: description)
    }
}

final class ZodAnyDef: ZodTypeDef {
    init(description: String? = nil) {
        super.init(typeName: .zodAny, description: description)
    }
}

final class ZodUnknownDef: ZodTypeDef {
    init(description: String? = nil) {
        super.init(typeName: .zodUnknown, description: description)
    }
}

final class ZodArrayDef: ZodTypeDef {
    let type: ZodSchema
    let minLength: ZodArraySizeCheck?
    let maxLength: ZodArraySizeCheck?
    let exactLength: ZodArraySizeCheck?

    init(
        type: ZodSchema,
        minLength: ZodArraySizeCheck? = nil,
        maxLength: ZodArraySizeCheck? = nil,
        exactLength: ZodArraySizeCheck? = nil,
        description: String? = nil
    ) {
        self.type = type
        self.minLength = minLength
        self.maxLength = maxLength
        self.exactLength = exactLength
        super.init(typeName: .zodArray, description: description)
    }
}

final class ZodIntersectionDef: ZodTypeDef {
    let left: ZodSchema
    let right: ZodSchema

    init(left: ZodSchema, right: ZodSchema, description: String? = nil) {
        self.left = left
        self.right = right
        super.init(typeName: .zodIntersection, description: description)
    }
}

final class ZodLiteralDef: ZodTypeDef {
    let value: Any

    init(value: Any, description: String? = nil) {
        self.value = value
        super.init(typeName: .zodLiteral, description: description)
    }
}

final class ZodEnumDef: ZodTypeDef {
    let values: [String]

    init(values: [String], description: String? = nil) {
        self.values = values
        super.init(typeName: .zodEnum, description: description)
    }
}

enum ZodNativeEnumValue: Sendable, Equatable {
    case string(String)
    case number(Int)
}

final class ZodNativeEnumDef: ZodTypeDef {
    let values: [String: ZodNativeEnumValue]

    init(values: [String: ZodNativeEnumValue], description: String? = nil) {
        self.values = values
        super.init(typeName: .zodNativeEnum, description: description)
    }
}

final class ZodUnionOptions: @unchecked Sendable {
    enum Storage: Sendable {
        case array([ZodSchema])
        case map([(String, ZodSchema)])
    }

    private let storage: Storage

    init(array: [ZodSchema]) {
        self.storage = .array(array)
    }

    init(map: [(String, ZodSchema)]) {
        self.storage = .map(map)
    }

    var values: [ZodSchema] {
        switch storage {
        case .array(let array):
            return array
        case .map(let entries):
            return entries.map(\.1)
        }
    }

    var isMap: Bool {
        if case .map = storage {
            return true
        }
        return false
    }
}

class ZodUnionBaseDef: ZodTypeDef {
    let options: ZodUnionOptions

    init(typeName: ZodFirstPartyTypeKind, options: ZodUnionOptions, description: String? = nil) {
        self.options = options
        super.init(typeName: typeName, description: description)
    }
}

final class ZodUnionDef: ZodUnionBaseDef {
    init(options: [ZodSchema], description: String? = nil) {
        super.init(typeName: .zodUnion, options: ZodUnionOptions(array: options), description: description)
    }
}

final class ZodDiscriminatedUnionDef: ZodUnionBaseDef {
    let discriminator: String

    init(discriminator: String, options: [(String, ZodSchema)], description: String? = nil) {
        self.discriminator = discriminator
        super.init(
            typeName: .zodDiscriminatedUnion,
            options: ZodUnionOptions(map: options),
            description: description
        )
    }
}

final class ZodTupleDef: ZodTypeDef {
    let items: [ZodSchema]
    let rest: ZodSchema?

    init(items: [ZodSchema], rest: ZodSchema? = nil, description: String? = nil) {
        self.items = items
        self.rest = rest
        super.init(typeName: .zodTuple, description: description)
    }
}

final class ZodNullableDef: ZodTypeDef {
    let innerType: ZodSchema

    init(innerType: ZodSchema, description: String? = nil) {
        self.innerType = innerType
        super.init(typeName: .zodNullable, description: description)
    }
}

final class ZodOptionalDef: ZodTypeDef {
    let innerType: ZodSchema

    init(innerType: ZodSchema, description: String? = nil) {
        self.innerType = innerType
        super.init(typeName: .zodOptional, description: description)
    }
}

final class ZodMapDef: ZodTypeDef {
    let keyType: ZodSchema
    let valueType: ZodSchema

    init(keyType: ZodSchema, valueType: ZodSchema, description: String? = nil) {
        self.keyType = keyType
        self.valueType = valueType
        super.init(typeName: .zodMap, description: description)
    }
}

final class ZodRecordDef: ZodTypeDef {
    let keyType: ZodSchema
    let valueType: ZodSchema

    init(keyType: ZodSchema, valueType: ZodSchema, description: String? = nil) {
        self.keyType = keyType
        self.valueType = valueType
        super.init(typeName: .zodRecord, description: description)
    }
}

final class ZodSetDef: ZodTypeDef {
    let valueType: ZodSchema
    let minSize: ZodSetSizeCheck?
    let maxSize: ZodSetSizeCheck?

    init(
        valueType: ZodSchema,
        minSize: ZodSetSizeCheck? = nil,
        maxSize: ZodSetSizeCheck? = nil,
        description: String? = nil
    ) {
        self.valueType = valueType
        self.minSize = minSize
        self.maxSize = maxSize
        super.init(typeName: .zodSet, description: description)
    }
}

final class ZodPromiseDef: ZodTypeDef {
    let type: ZodSchema

    init(type: ZodSchema, description: String? = nil) {
        self.type = type
        super.init(typeName: .zodPromise, description: description)
    }
}

final class ZodEffectsDef: ZodTypeDef {
    let schema: ZodSchema

    init(schema: ZodSchema, description: String? = nil) {
        self.schema = schema
        super.init(typeName: .zodEffects, description: description)
    }
}

final class ZodDefaultDef: ZodTypeDef {
    let innerType: ZodSchema
    let defaultValue: @Sendable () -> Any

    init(innerType: ZodSchema, defaultValue: @escaping @Sendable () -> Any, description: String? = nil) {
        self.innerType = innerType
        self.defaultValue = defaultValue
        super.init(typeName: .zodDefault, description: description)
    }
}

final class ZodBrandedDef: ZodTypeDef {
    let type: ZodSchema

    init(type: ZodSchema, description: String? = nil) {
        self.type = type
        super.init(typeName: .zodBranded, description: description)
    }
}

final class ZodReadonlyDef: ZodTypeDef {
    let innerType: ZodSchema

    init(innerType: ZodSchema, description: String? = nil) {
        self.innerType = innerType
        super.init(typeName: .zodReadonly, description: description)
    }
}

final class ZodCatchDef: ZodTypeDef {
    let innerType: ZodSchema

    init(innerType: ZodSchema, description: String? = nil) {
        self.innerType = innerType
        super.init(typeName: .zodCatch, description: description)
    }
}

final class ZodPipelineDef: ZodTypeDef {
    let input: ZodSchema
    let output: ZodSchema

    init(input: ZodSchema, output: ZodSchema, description: String? = nil) {
        self.input = input
        self.output = output
        super.init(typeName: .zodPipeline, description: description)
    }
}

final class ZodLazyDef: ZodTypeDef, @unchecked Sendable {
    let getter: @Sendable () -> ZodSchema

    init(getter: @escaping @Sendable () -> ZodSchema, description: String? = nil) {
        self.getter = getter
        super.init(typeName: .zodLazy, description: description)
    }
}

enum ZodObjectUnknownKeys: Sendable {
    case passthrough
    case strict
    case strip
}

final class ZodObjectDef: ZodTypeDef, @unchecked Sendable {
    let shape: @Sendable () -> [String: ZodSchema]
    let unknownKeys: ZodObjectUnknownKeys
    let catchall: ZodSchema

    init(
        shape: @escaping @Sendable () -> [String: ZodSchema],
        unknownKeys: ZodObjectUnknownKeys,
        catchall: ZodSchema,
        description: String? = nil
    ) {
        self.shape = shape
        self.unknownKeys = unknownKeys
        self.catchall = catchall
        super.init(typeName: .zodObject, description: description)
    }
}

// MARK: - Sendable Conformances

extension ZodStringDef: @unchecked Sendable {}
extension ZodNumberDef: @unchecked Sendable {}
extension ZodBigIntDef: @unchecked Sendable {}
extension ZodBooleanDef: @unchecked Sendable {}
extension ZodDateDef: @unchecked Sendable {}
extension ZodUndefinedDef: @unchecked Sendable {}
extension ZodNullDef: @unchecked Sendable {}
extension ZodNeverDef: @unchecked Sendable {}
extension ZodNaNDef: @unchecked Sendable {}
extension ZodAnyDef: @unchecked Sendable {}
extension ZodUnknownDef: @unchecked Sendable {}
extension ZodArrayDef: @unchecked Sendable {}
extension ZodIntersectionDef: @unchecked Sendable {}
extension ZodLiteralDef: @unchecked Sendable {}
extension ZodEnumDef: @unchecked Sendable {}
extension ZodNativeEnumDef: @unchecked Sendable {}
extension ZodUnionBaseDef: @unchecked Sendable {}
extension ZodUnionDef: @unchecked Sendable {}
extension ZodDiscriminatedUnionDef: @unchecked Sendable {}
extension ZodTupleDef: @unchecked Sendable {}
extension ZodNullableDef: @unchecked Sendable {}
extension ZodOptionalDef: @unchecked Sendable {}
extension ZodMapDef: @unchecked Sendable {}
extension ZodRecordDef: @unchecked Sendable {}
extension ZodSetDef: @unchecked Sendable {}
extension ZodPromiseDef: @unchecked Sendable {}
extension ZodEffectsDef: @unchecked Sendable {}
extension ZodDefaultDef: @unchecked Sendable {}
extension ZodBrandedDef: @unchecked Sendable {}
extension ZodReadonlyDef: @unchecked Sendable {}
extension ZodCatchDef: @unchecked Sendable {}
extension ZodPipelineDef: @unchecked Sendable {}
