import AISDKProvider
import Foundation

// MARK: - Primitive Mappings

let primitiveMappings: [ZodFirstPartyTypeKind: String] = [
    .zodString: "string",
    .zodNumber: "number",
    .zodBigInt: "integer",
    .zodBoolean: "boolean",
    .zodNull: "null",
]

let alphaNumericCharacters: Set<Character> = Set(
    "ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvxyz0123456789")

private func hasChecks(_ def: ZodTypeDef) -> Bool {
    switch def {
    case let stringDef as ZodStringDef:
        return !stringDef.checks.isEmpty
    case let numberDef as ZodNumberDef:
        return !numberDef.checks.isEmpty
    case let bigIntDef as ZodBigIntDef:
        return !bigIntDef.checks.isEmpty
    case let dateDef as ZodDateDef:
        return !dateDef.checks.isEmpty
    case let arrayDef as ZodArrayDef:
        return arrayDef.minLength != nil || arrayDef.maxLength != nil || arrayDef.exactLength != nil
    case let setDef as ZodSetDef:
        return setDef.minSize != nil || setDef.maxSize != nil
    default:
        return false
    }
}

extension JSONValue {
    fileprivate var stringValue: String? {
        if case .string(let value) = self {
            return value
        }
        return nil
    }

    fileprivate var doubleValue: Double? {
        if case .number(let value) = self {
            return value
        }
        return nil
    }

    fileprivate var arrayValue: [JSONValue]? {
        if case .array(let array) = self {
            return array
        }
        return nil
    }

    fileprivate var objectValue: JsonSchemaObject? {
        if case .object(let object) = self {
            return object
        }
        return nil
    }
}

extension Character {
    fileprivate var isLowercaseASCII: Bool {
        guard let scalar = unicodeScalars.first, unicodeScalars.count == 1 else { return false }
        return scalar >= "a" && scalar <= "z"
    }
}

// MARK: - Basic Parsers

func parseAnyDef() -> JsonSchemaObject {
    [:]
}

func parseBooleanDef() -> JsonSchemaObject {
    ["type": .string("boolean")]
}

func parseNullDef() -> JsonSchemaObject {
    ["type": .string("null")]
}

func parseUndefinedDef() -> JsonSchemaObject {
    ["not": .object(parseAnyDef())]
}

func parseUnknownDef() -> JsonSchemaObject {
    parseAnyDef()
}

func parseNeverDef() -> JsonSchemaObject {
    ["not": .object(parseAnyDef())]
}

func parseNumberDef(_ def: ZodNumberDef) -> JsonSchemaObject {
    var schema: JsonSchemaObject = ["type": .string("number")]

    for check in def.checks {
        switch check {
        case .int:
            schema["type"] = .string("integer")
        case .min(let bound):
            if bound.inclusive {
                schema["minimum"] = .number(Double(bound.value))
            } else {
                schema["exclusiveMinimum"] = .number(Double(bound.value))
            }
        case .max(let bound):
            if bound.inclusive {
                schema["maximum"] = .number(Double(bound.value))
            } else {
                schema["exclusiveMaximum"] = .number(Double(bound.value))
            }
        case .multipleOf(let value):
            schema["multipleOf"] = .number(Double(value))
        }
    }

    return schema
}

func parseBigintDef(_ def: ZodBigIntDef) -> JsonSchemaObject {
    var schema: JsonSchemaObject = [
        "type": .string("integer"),
        "format": .string("int64"),
    ]

    for check in def.checks {
        switch check {
        case .min(let bound):
            if bound.inclusive {
                schema["minimum"] = .number(Double(bound.value))
            } else {
                schema["exclusiveMinimum"] = .number(Double(bound.value))
            }
        case .max(let bound):
            if bound.inclusive {
                schema["maximum"] = .number(Double(bound.value))
            } else {
                schema["exclusiveMaximum"] = .number(Double(bound.value))
            }
        case .multipleOf(let value):
            schema["multipleOf"] = .number(Double(value))
        }
    }

    return schema
}

func parseArrayDef(_ def: ZodArrayDef, _ refs: Refs) -> JsonSchemaObject {
    var schema: JsonSchemaObject = ["type": .string("array")]

    if def.type._def.typeName != .zodAny {
        if let items = parseDef(
            def.type._def,
            refs.with(currentPath: refs.currentPath + ["items"]),
            false
        ) {
            schema["items"] = .object(items)
        }
    }

    if let minLength = def.minLength {
        schema["minItems"] = .number(Double(minLength.value))
    }

    if let maxLength = def.maxLength {
        schema["maxItems"] = .number(Double(maxLength.value))
    }

    if let exact = def.exactLength {
        let value = Double(exact.value)
        schema["minItems"] = .number(value)
        schema["maxItems"] = .number(value)
    }

    return schema
}

func parseTupleDef(_ def: ZodTupleDef, _ refs: Refs) -> JsonSchemaObject {
    var schema: JsonSchemaObject = [
        "type": .string("array"),
        "minItems": .number(Double(def.items.count)),
    ]

    let itemSchemas: [JSONValue] = def.items.enumerated().compactMap { index, item in
        parseDef(
            item._def,
            refs.with(currentPath: refs.currentPath + ["items", "\(index)"]),
            false
        ).map(JSONValue.object)
    }

    schema["items"] = .array(itemSchemas)

    if let rest = def.rest {
        if let restSchema = parseDef(
            rest._def,
            refs.with(currentPath: refs.currentPath + ["additionalItems"]),
            false
        ) {
            schema["additionalItems"] = .object(restSchema)
        }
    } else {
        schema["maxItems"] = .number(Double(def.items.count))
    }

    return schema
}

func parseSetDef(_ def: ZodSetDef, _ refs: Refs) -> JsonSchemaObject {
    var schema: JsonSchemaObject = [
        "type": .string("array"),
        "uniqueItems": .bool(true),
    ]

    if let items = parseDef(
        def.valueType._def,
        refs.with(currentPath: refs.currentPath + ["items"]),
        false
    ) {
        schema["items"] = .object(items)
    }

    if let minSize = def.minSize {
        schema["minItems"] = .number(Double(minSize.value))
    }

    if let maxSize = def.maxSize {
        schema["maxItems"] = .number(Double(maxSize.value))
    }

    return schema
}

func parsePromiseDef(_ def: ZodPromiseDef, _ refs: Refs) -> JsonSchemaObject? {
    parseDef(def.type._def, refs, false)
}

func parseEffectsDef(_ def: ZodEffectsDef, _ refs: Refs) -> JsonSchemaObject? {
    switch refs.effectStrategy {
    case .input:
        return parseDef(def.schema._def, refs, false)
    case .any:
        return parseAnyDef()
    }
}

func parseDefaultDef(_ def: ZodDefaultDef, _ refs: Refs) -> JsonSchemaObject? {
    guard var schema = parseDef(def.innerType._def, refs, false) else {
        return nil
    }

    let defaultValue = def.defaultValue()
    if let jsonDefault = try? jsonValue(from: defaultValue) {
        schema["default"] = jsonDefault
    }

    return schema
}

func parseBrandedDef(_ def: ZodBrandedDef, _ refs: Refs) -> JsonSchemaObject? {
    parseDef(def.type._def, refs, false)
}

func parseReadonlyDef(_ def: ZodReadonlyDef, _ refs: Refs) -> JsonSchemaObject? {
    parseDef(def.innerType._def, refs, false)
}

func parseCatchDef(_ def: ZodCatchDef, _ refs: Refs) -> JsonSchemaObject? {
    parseDef(def.innerType._def, refs, false)
}

func parseOptionalDef(_ def: ZodOptionalDef, _ refs: Refs) -> JsonSchemaObject? {
    if refs.currentPath == refs.propertyPath {
        return parseDef(def.innerType._def, refs, false)
    }

    let innerRefs = refs.with(currentPath: refs.currentPath + ["anyOf", "1"])
    guard let innerSchema = parseDef(def.innerType._def, innerRefs, false) else {
        return parseAnyDef()
    }

    let anySchema: JsonSchemaObject = ["not": .object(parseAnyDef())]

    return [
        "anyOf": .array([
            .object(anySchema),
            .object(innerSchema),
        ])
    ]
}

func parsePipelineDef(_ def: ZodPipelineDef, _ refs: Refs) -> JsonSchemaObject? {
    switch refs.pipeStrategy {
    case .input:
        return parseDef(def.input._def, refs, false)
    case .output:
        return parseDef(def.output._def, refs, false)
    case .all:
        let first = parseDef(
            def.input._def,
            refs.with(currentPath: refs.currentPath + ["allOf", "0"]),
            false
        )

        let secondIndex = first == nil ? "0" : "1"
        let second = parseDef(
            def.output._def,
            refs.with(currentPath: refs.currentPath + ["allOf", secondIndex]),
            false
        )

        let schemas = [first, second].compactMap { $0 }
        guard !schemas.isEmpty else { return nil }
        return ["allOf": .array(schemas.map(JSONValue.object))]
    }
}

func parseNullableDef(_ def: ZodNullableDef, _ refs: Refs) -> JsonSchemaObject? {
    let innerDef = def.innerType._def
    if let primitive = primitiveMappings[innerDef.typeName], !hasChecks(innerDef) {
        return [
            "type": .array([
                .string(primitive),
                .string("null"),
            ])
        ]
    }

    guard
        let base = parseDef(
            innerDef,
            refs.with(currentPath: refs.currentPath + ["anyOf", "0"]),
            false
        )
    else {
        return nil
    }

    return [
        "anyOf": .array([
            .object(base),
            .object(["type": .string("null")]),
        ])
    ]
}

func parseLiteralDef(_ def: ZodLiteralDef) -> JsonSchemaObject {
    switch def.value {
    case let string as String:
        return [
            "type": .string("string"),
            "const": .string(string),
        ]
    case let bool as Bool:
        return [
            "type": .string("boolean"),
            "const": .bool(bool),
        ]
    case let number as Double:
        return [
            "type": .string("number"),
            "const": .number(number),
        ]
    case let number as Float:
        return [
            "type": .string("number"),
            "const": .number(Double(number)),
        ]
    case let number as Int:
        return [
            "type": .string("number"),
            "const": .number(Double(number)),
        ]
    case let number as NSNumber:
        if CFGetTypeID(number) == CFBooleanGetTypeID() {
            let boolValue = number.boolValue
            return [
                "type": .string("boolean"),
                "const": .bool(boolValue),
            ]
        } else {
            return [
                "type": .string("number"),
                "const": .number(number.doubleValue),
            ]
        }
    case is [Any]:
        return ["type": .string("array")]
    case is [String: Any]:
        return ["type": .string("object")]
    case is NSNull:
        return ["type": .string("object")]
    default:
        if let json = try? jsonValue(from: def.value) {
            switch json {
            case .string(let value):
                return [
                    "type": .string("string"),
                    "const": .string(value),
                ]
            case .number(let value):
                return [
                    "type": .string("number"),
                    "const": .number(value),
                ]
            case .bool(let bool):
                return [
                    "type": .string("boolean"),
                    "const": .bool(bool),
                ]
            case .null:
                return ["type": .string("object")]
            case .array:
                return ["type": .string("array")]
            case .object:
                return ["type": .string("object")]
            }
        }

        return ["type": .string("object")]
    }
}

func parseEnumDef(_ def: ZodEnumDef) -> JsonSchemaObject {
    [
        "type": .string("string"),
        "enum": .array(def.values.map(JSONValue.string)),
    ]
}

func parseNativeEnumDef(_ def: ZodNativeEnumDef) -> JsonSchemaObject {
    let entries = def.values

    let actualKeys: [String] = entries.keys.filter { key in
        guard let value = entries[key] else { return false }
        if case let .number(index) = value, let linked = entries["\(index)"] {
            if case .number = linked {
                return true
            } else {
                return false
            }
        }
        return true
    }

    let actualValues: [ZodNativeEnumValue] = actualKeys.compactMap { entries[$0] }
    let parsedTypes = Set(
        actualValues.map { value -> String in
            switch value {
            case .string:
                return "string"
            case .number:
                return "number"
            }
        })

    let typeValue: JSONValue
    if parsedTypes.count == 1, let first = parsedTypes.first {
        typeValue = .string(first)
    } else {
        typeValue = .array(parsedTypes.sorted().map(JSONValue.string))
    }

    let enumValues: [JSONValue] = actualValues.map { value in
        switch value {
        case .string(let string):
            return .string(string)
        case .number(let number):
            return .number(Double(number))
        }
    }

    return [
        "type": typeValue,
        "enum": .array(enumValues),
    ]
}

func parseStringDef(_ def: ZodStringDef, _ refs: Refs) -> JsonSchemaObject {
    var schema: JsonSchemaObject = ["type": .string("string")]

    for check in def.checks {
        switch check {
        case .min(let value, _):
            setMinLength(&schema, value: value)
        case .max(let value, _):
            setMaxLength(&schema, value: value)
        case .length(let value, _):
            setMinLength(&schema, value: value)
            setMaxLength(&schema, value: value)
        case .email(let message):
            switch refs.emailStrategy {
            case .formatEmail:
                addFormat(&schema, value: "email", message: message, refs: refs)
            case .formatIdnEmail:
                addFormat(&schema, value: "idn-email", message: message, refs: refs)
            case .patternZod:
                addPattern(&schema, regex: ZodPatterns.email, message: message, refs: refs)
            }
        case .url(let message):
            addFormat(&schema, value: "uri", message: message, refs: refs)
        case .uuid(let message):
            addFormat(&schema, value: "uuid", message: message, refs: refs)
        case .regex(let pattern, let message):
            addPattern(&schema, regex: pattern, message: message, refs: refs)
        case .cuid(let message):
            addPattern(&schema, regex: ZodPatterns.cuid, message: message, refs: refs)
        case .cuid2(let message):
            addPattern(&schema, regex: ZodPatterns.cuid2, message: message, refs: refs)
        case .startsWith(let value, let message):
            let escaped = escapeLiteralCheckValue(value, refs: refs)
            addPattern(
                &schema,
                regex: ZodRegexPattern(pattern: "^\(escaped)"),
                message: message,
                refs: refs
            )
        case .endsWith(let value, let message):
            let escaped = escapeLiteralCheckValue(value, refs: refs)
            addPattern(
                &schema,
                regex: ZodRegexPattern(pattern: "\(escaped)$"),
                message: message,
                refs: refs
            )
        case .datetime(let message):
            addFormat(&schema, value: "date-time", message: message, refs: refs)
        case .date(let message):
            addFormat(&schema, value: "date", message: message, refs: refs)
        case .time(let message):
            addFormat(&schema, value: "time", message: message, refs: refs)
        case .duration(let message):
            addFormat(&schema, value: "duration", message: message, refs: refs)
        case .includes(let value, let message):
            let escaped = escapeLiteralCheckValue(value, refs: refs)
            addPattern(
                &schema,
                regex: ZodRegexPattern(pattern: escaped),
                message: message,
                refs: refs
            )
        case .ip(let version, let message):
            if version != .v6 {
                addFormat(&schema, value: "ipv4", message: message, refs: refs)
            }
            if version != .v4 {
                addFormat(&schema, value: "ipv6", message: message, refs: refs)
            }
        case .emoji(let message):
            addPattern(&schema, regex: ZodPatterns.emoji(), message: message, refs: refs)
        case .ulid(let message):
            addPattern(&schema, regex: ZodPatterns.ulid, message: message, refs: refs)
        case .base64(let message):
            switch refs.base64Strategy {
            case .contentEncodingBase64:
                schema["contentEncoding"] = .string("base64")
            case .formatBinary:
                addFormat(&schema, value: "binary", message: message, refs: refs)
            case .patternZod:
                addPattern(&schema, regex: ZodPatterns.base64, message: message, refs: refs)
            }
        case .base64url(let message):
            addPattern(&schema, regex: ZodPatterns.base64url, message: message, refs: refs)
        case .jwt(let message):
            addPattern(&schema, regex: ZodPatterns.jwt, message: message, refs: refs)
        case .cidr(let version, let message):
            if version != .v6 {
                addPattern(&schema, regex: ZodPatterns.ipv4Cidr, message: message, refs: refs)
            }
            if version != .v4 {
                addPattern(&schema, regex: ZodPatterns.ipv6Cidr, message: message, refs: refs)
            }
        case .nanoid(let message):
            addPattern(&schema, regex: ZodPatterns.nanoid, message: message, refs: refs)
        case .toLowerCase, .toUpperCase, .trim:
            continue
        }
    }

    return schema
}

private func setMinLength(_ schema: inout JsonSchemaObject, value: Int) {
    let newValue = Double(value)
    if let existing = schema["minLength"]?.doubleValue {
        schema["minLength"] = .number(max(existing, newValue))
    } else {
        schema["minLength"] = .number(newValue)
    }
}

private func setMaxLength(_ schema: inout JsonSchemaObject, value: Int) {
    let newValue = Double(value)
    if let existing = schema["maxLength"]?.doubleValue {
        schema["maxLength"] = .number(min(existing, newValue))
    } else {
        schema["maxLength"] = .number(newValue)
    }
}

private func addFormat(
    _ schema: inout JsonSchemaObject,
    value: String,
    message: String?,
    refs: Refs
) {
    if let existingFormat = schema["format"]?.stringValue {
        var anyOf = schema["anyOf"]?.arrayValue ?? []
        anyOf.append(.object(["format": .string(existingFormat)]))
        schema.removeValue(forKey: "format")
        var entry: JsonSchemaObject = ["format": .string(value)]
        if let message, refs.errorMessages {
            entry["errorMessage"] = .object(["format": .string(message)])
        }
        anyOf.append(.object(entry))
        schema["anyOf"] = .array(anyOf)
        return
    }

    if var anyOf = schema["anyOf"]?.arrayValue,
       anyOf.contains(where: { $0.objectValue?["format"] != nil }) {
        var entry: JsonSchemaObject = ["format": .string(value)]
        if let message, refs.errorMessages {
            entry["errorMessage"] = .object(["format": .string(message)])
        }
        anyOf.append(.object(entry))
        schema["anyOf"] = .array(anyOf)
        return
    }

    schema["format"] = .string(value)
}

private func addPattern(
    _ schema: inout JsonSchemaObject,
    regex: ZodRegexPattern,
    message: String?,
    refs: Refs
) {
    let pattern = stringifyRegExpWithFlags(regex, refs: refs)

    if let existingPattern = schema["pattern"]?.stringValue {
        var allOf = schema["allOf"]?.arrayValue ?? []
        allOf.append(.object(["pattern": .string(existingPattern)]))
        schema.removeValue(forKey: "pattern")
        var entry: JsonSchemaObject = ["pattern": .string(pattern)]
        if let message, refs.errorMessages {
            entry["errorMessage"] = .object(["pattern": .string(message)])
        }
        allOf.append(.object(entry))
        schema["allOf"] = .array(allOf)
        return
    }

    if var allOf = schema["allOf"]?.arrayValue,
       allOf.contains(where: { $0.objectValue?["pattern"] != nil }) {
        var entry: JsonSchemaObject = ["pattern": .string(pattern)]
        if let message, refs.errorMessages {
            entry["errorMessage"] = .object(["pattern": .string(message)])
        }
        allOf.append(.object(entry))
        schema["allOf"] = .array(allOf)
        return
    }

    schema["pattern"] = .string(pattern)
}

private func escapeLiteralCheckValue(_ literal: String, refs: Refs) -> String {
    switch refs.patternStrategy {
    case .escape:
        return escapeNonAlphaNumeric(literal)
    case .preserve:
        return literal
    }
}

private func escapeNonAlphaNumeric(_ source: String) -> String {
    var result = ""
    for character in source {
        if !alphaNumericCharacters.contains(character) {
            result.append("\\")
        }
        result.append(character)
    }
    return result
}

private func stringifyRegExpWithFlags(
    _ regex: ZodRegexPattern,
    refs: Refs
) -> String {
    guard refs.applyRegexFlags, !regex.flags.isEmpty else {
        return regex.pattern
    }

    let hasI = regex.flags.contains("i")
    let hasM = regex.flags.contains("m")
    let hasS = regex.flags.contains("s")

    let source = hasI ? regex.pattern.lowercased() : regex.pattern
    var pattern = ""
    var isEscaped = false
    var inCharGroup = false
    var inCharRange = false

    let characters = Array(source)

    for index in characters.indices {
        let character = characters[index]

        if isEscaped {
            pattern.append(character)
            isEscaped = false
            continue
        }

        if hasI {
            if inCharGroup {
                if character.isLowercaseASCII {
                    if inCharRange {
                        pattern.append(character)
                        if index >= 2 {
                            let startChar = characters[index - 2]
                            pattern.append(contentsOf: "\(startChar)-\(character)".uppercased())
                        }
                        inCharRange = false
                    } else if index + 2 < characters.count,
                              characters[index + 1] == "-",
                              characters[index + 2].isLowercaseASCII {
                        pattern.append(character)
                        inCharRange = true
                    } else {
                        pattern.append(character)
                        pattern.append(contentsOf: String(character).uppercased())
                    }
                    continue
                }
            } else if character.isLowercaseASCII {
                pattern.append("[")
                pattern.append(character)
                pattern.append(contentsOf: String(character).uppercased())
                pattern.append("]")
                continue
            }
        }

        if hasM {
            if character == "^" {
                pattern.append("(^|(?<=[\\r\\n]))")
                continue
            } else if character == "$" {
                pattern.append("($|(?=[\\r\\n]))")
                continue
            }
        }

        if hasS && character == "." {
            if inCharGroup {
                pattern.append(character)
                pattern.append("\\r\\n")
            } else {
                pattern.append("[")
                pattern.append(character)
                pattern.append("\\r\\n]")
            }
            continue
        }

        pattern.append(character)
        if character == "\\" {
            isEscaped = true
        } else if inCharGroup && character == "]" {
            inCharGroup = false
            inCharRange = false
        } else if !inCharGroup && character == "[" {
            inCharGroup = true
        } else if inCharGroup && character == "-" {
            inCharRange = true
        }
    }

    do {
        _ = try NSRegularExpression(pattern: pattern)
    } catch {
        print("Could not convert regex pattern at \(refs.currentPath.joined(separator: "/")) to a flag-independent form. Using original source.")
        return regex.pattern
    }

    return pattern
}

func parseDateDef(
    _ def: ZodDateDef,
    _ refs: Refs,
    override: DateStrategy? = nil
) -> JsonSchemaObject {
    let strategySetting: DateStrategySetting
    if let override {
        strategySetting = .single(override)
    } else {
        strategySetting = refs.dateStrategy
    }

    switch strategySetting {
    case .single(let strategy):
        switch strategy {
        case .string, .formatDateTime:
            return [
                "type": .string("string"),
                "format": .string("date-time"),
            ]
        case .formatDate:
            return [
                "type": .string("string"),
                "format": .string("date"),
            ]
        case .integer:
            return integerDateParser(def)
        }
    case .multiple(let strategies):
        let schemas = strategies.enumerated().map { index, item in
            parseDateDef(
                def,
                refs.with(currentPath: refs.currentPath + ["anyOf", "\(index)"]),
                override: item
            )
        }

        return [
            "anyOf": .array(schemas.map(JSONValue.object))
        ]
    }
}

private func integerDateParser(_ def: ZodDateDef) -> JsonSchemaObject {
    var schema: JsonSchemaObject = [
        "type": .string("integer"),
        "format": .string("unix-time"),
    ]

    for check in def.checks {
        switch check {
        case .min(let value):
            schema["minimum"] = .number(value)
        case .max(let value):
            schema["maximum"] = .number(value)
        }
    }

    return schema
}

func parseRecordDef(
    _ def: ZodRecordDef,
    _ refs: Refs
) -> JsonSchemaObject {
    var schema: JsonSchemaObject = [
        "type": .string("object")
    ]

    if let additionalProps = parseDef(
        def.valueType._def,
        refs.with(currentPath: refs.currentPath + ["additionalProperties"]),
        false
    ) {
        schema["additionalProperties"] = .object(additionalProps)
    } else if let allowed = refs.allowedAdditionalProperties {
        schema["additionalProperties"] = .bool(allowed)
    }

    let keyDef = def.keyType._def

    if let stringKey = keyDef as? ZodStringDef, !stringKey.checks.isEmpty {
        var propertyNames = parseStringDef(stringKey, refs)
        propertyNames.removeValue(forKey: "type")
        if !propertyNames.isEmpty {
            schema["propertyNames"] = .object(propertyNames)
        }
    } else if let enumKey = keyDef as? ZodEnumDef {
        schema["propertyNames"] = .object([
            "enum": .array(enumKey.values.map(JSONValue.string))
        ])
    } else if let brandedKey = keyDef as? ZodBrandedDef,
        let stringInner = brandedKey.type._def as? ZodStringDef,
        !stringInner.checks.isEmpty
    {
        var propertyNames = parseStringDef(stringInner, refs)
        propertyNames.removeValue(forKey: "type")
        if !propertyNames.isEmpty {
            schema["propertyNames"] = .object(propertyNames)
        }
    }

    return schema
}

func parseMapDef(_ def: ZodMapDef, _ refs: Refs) -> JsonSchemaObject {
    if refs.mapStrategy == .record {
        return parseRecordDef(
            ZodRecordDef(keyType: def.keyType, valueType: def.valueType),
            refs
        )
    }

    let keyPath = refs.with(currentPath: refs.currentPath + ["items", "items", "0"])
    let valuePath = refs.with(currentPath: refs.currentPath + ["items", "items", "1"])

    let keySchema = parseDef(def.keyType._def, keyPath, false) ?? parseAnyDef()
    let valueSchema = parseDef(def.valueType._def, valuePath, false) ?? parseAnyDef()

    return [
        "type": .string("array"),
        "maxItems": .number(125),
        "items": .object([
            "type": .string("array"),
            "items": .array([
                .object(keySchema),
                .object(valueSchema),
            ]),
            "minItems": .number(2),
            "maxItems": .number(2),
        ]),
    ]
}

func parseObjectDef(_ def: ZodObjectDef, _ refs: Refs) -> JsonSchemaObject {
    var properties: [String: JSONValue] = [:]
    var required: [String] = []

    let shape = def.shape()

    for (name, schema) in shape {
        let propertyPath = refs.currentPath + ["properties", name]
        let propertyRefs = refs.with(currentPath: propertyPath, propertyPath: propertyPath)

        guard let parsed = parseDef(schema._def, propertyRefs, false) else {
            continue
        }

        properties[name] = .object(parsed)

        if !schema.isOptional() {
            required.append(name)
        }
    }

    var result: JsonSchemaObject = [
        "type": .string("object"),
        "properties": .object(properties),
    ]

    if !required.isEmpty {
        result["required"] = .array(required.map(JSONValue.string))
    }

    if let additional = decideAdditionalProperties(def, refs) {
        result["additionalProperties"] = additional
    }

    return result
}

private func decideAdditionalProperties(_ def: ZodObjectDef, _ refs: Refs) -> JSONValue? {
    if def.catchall._def.typeName != .zodNever {
        return parseDef(
            def.catchall._def,
            refs.with(currentPath: refs.currentPath + ["additionalProperties"]),
            false
        ).map(JSONValue.object)
    }

    switch def.unknownKeys {
    case .passthrough:
        if let allowed = refs.allowedAdditionalProperties {
            return .bool(allowed)
        }
        return nil
    case .strict:
        if let rejected = refs.rejectedAdditionalProperties {
            return .bool(rejected)
        }
        return nil
    case .strip:
        switch refs.options.removeAdditionalStrategy {
        case .strict:
            if let allowed = refs.allowedAdditionalProperties {
                return .bool(allowed)
            }
            return nil
        case .passthrough:
            if let rejected = refs.rejectedAdditionalProperties {
                return .bool(rejected)
            }
            return nil
        }
    }
}

func parseUnionDef(_ def: ZodUnionBaseDef, _ refs: Refs) -> JsonSchemaObject? {
    let options = def.options.values

    if options.allSatisfy({ option in
        primitiveMappings[option._def.typeName] != nil && !hasChecks(option._def)
    }) {
        var types: [String] = []
        for option in options {
            if let type = primitiveMappings[option._def.typeName], !types.contains(type) {
                types.append(type)
            }
        }

        if types.isEmpty {
            return nil
        }

        let typeValue: JSONValue =
            types.count == 1
            ? .string(types[0])
            : .array(types.map(JSONValue.string))

        return ["type": typeValue]
    }

    if options.allSatisfy({ schema in
        guard let literal = schema._def as? ZodLiteralDef else { return false }
        return literal.description == nil
    }) {
        var types: [String] = []
        var enumValues: [JSONValue] = []

        for schema in options {
            guard let literal = schema._def as? ZodLiteralDef else { continue }
            switch literal.value {
            case let value as String:
                types.append("string")
                if !enumValues.contains(.string(value)) {
                    enumValues.append(.string(value))
                }
            case let value as Bool:
                types.append("boolean")
                if !enumValues.contains(.bool(value)) {
                    enumValues.append(.bool(value))
                }
            case let value as Int:
                types.append("number")
                let jsonNumber = JSONValue.number(Double(value))
                if !enumValues.contains(jsonNumber) {
                    enumValues.append(jsonNumber)
                }
            case let value as Double:
                types.append("number")
                let jsonNumber = JSONValue.number(value)
                if !enumValues.contains(jsonNumber) {
                    enumValues.append(jsonNumber)
                }
            case let value as Float:
                types.append("number")
                let jsonNumber = JSONValue.number(Double(value))
                if !enumValues.contains(jsonNumber) {
                    enumValues.append(jsonNumber)
                }
            case is NSNull:
                types.append("null")
                if !enumValues.contains(.null) {
                    enumValues.append(.null)
                }
            default:
                continue
            }
        }

        if types.count == options.count {
            var uniqueTypes: [String] = []
            for type in types where !uniqueTypes.contains(type) {
                uniqueTypes.append(type)
            }
            let typeValue: JSONValue =
                uniqueTypes.count == 1
                ? .string(uniqueTypes[0])
                : .array(uniqueTypes.map(JSONValue.string))

            return [
                "type": typeValue,
                "enum": .array(enumValues),
            ]
        }
    }

    if options.allSatisfy({ $0._def is ZodEnumDef }) {
        var values: [String] = []
        for option in options {
            guard let enumDef = option._def as? ZodEnumDef else { continue }
            for value in enumDef.values where !values.contains(value) {
                values.append(value)
            }
        }

        return [
            "type": .string("string"),
            "enum": .array(values.map(JSONValue.string)),
        ]
    }

    return asAnyOf(def, refs)
}

private func asAnyOf(_ def: ZodUnionBaseDef, _ refs: Refs) -> JsonSchemaObject? {
    let schemas = def.options.values.enumerated().compactMap { index, schema in
        parseDef(
            schema._def,
            refs.with(currentPath: refs.currentPath + ["anyOf", "\(index)"]),
            false
        )
    }.filter { schema in
        guard refs.strictUnions else { return true }
        return !schema.isEmpty
    }

    guard !schemas.isEmpty else {
        return nil
    }

    return [
        "anyOf": .array(schemas.map(JSONValue.object))
    ]
}

func parseIntersectionDef(_ def: ZodIntersectionDef, _ refs: Refs) -> JsonSchemaObject? {
    let left = parseDef(
        def.left._def,
        refs.with(currentPath: refs.currentPath + ["allOf", "0"]),
        false
    )

    let right = parseDef(
        def.right._def,
        refs.with(currentPath: refs.currentPath + ["allOf", "1"]),
        false
    )

    let schemas = [left, right].compactMap { $0 }
    var merged: [JsonSchemaObject] = []

    for schema in schemas {
        if let allOfArray = schema["allOf"]?.arrayValue,
           schema["type"]?.stringValue != "string" {
            for element in allOfArray {
                if let object = element.objectValue {
                    merged.append(object)
                }
            }
        } else {
            var nested = schema
            if let additional = schema["additionalProperties"], additional == .bool(false) {
                nested.removeValue(forKey: "additionalProperties")
            }
            merged.append(nested)
        }
    }

    guard !merged.isEmpty else {
        return nil
    }

    return ["allOf": .array(merged.map(JSONValue.object))]
}
enum ZodPatterns {
    static let cuid = ZodRegexPattern(pattern: "^[cC][^\\s-]{8,}$")
    static let cuid2 = ZodRegexPattern(pattern: "^[0-9a-z]+$")
    static let ulid = ZodRegexPattern(pattern: "^[0-9A-HJKMNP-TV-Z]{26}$")
    static let email = ZodRegexPattern(
        pattern:
            "^(?!\\.)(?!.*\\.\\.)([a-zA-Z0-9_'+\\-\\.]*?)[a-zA-Z0-9_+-]@([a-zA-Z0-9][a-zA-Z0-9\\-]*\\.)+[a-zA-Z]{2,}$"
    )
    private static let emojiPattern: ZodRegexPattern = ZodRegexPattern(
        pattern: "^(\\p{Extended_Pictographic}|\\p{Emoji_Component})+$",
        flags: "u"
    )
    static func emoji() -> ZodRegexPattern {
        emojiPattern
    }
    static let uuid = ZodRegexPattern(
        pattern:
            "^[0-9a-fA-F]{8}\\b-[0-9a-fA-F]{4}\\b-[0-9a-fA-F]{4}\\b-[0-9a-fA-F]{4}\\b-[0-9a-fA-F]{12}$"
    )
    static let ipv4 = ZodRegexPattern(
        pattern:
            "^(?:(?:25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]|[0-9])\\.){3}(?:25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]|[0-9])$"
    )
    static let ipv4Cidr = ZodRegexPattern(
        pattern:
            "^(?:(?:25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]|[0-9])\\.){3}(?:25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]|[0-9])\\/(3[0-2]|[12]?[0-9])$"
    )
    static let ipv6 = ZodRegexPattern(
        pattern:
            "^(([a-f0-9]{1,4}:){7}|::([a-f0-9]{1,4}:){0,6}|([a-f0-9]{1,4}:){1}:([a-f0-9]{1,4}:){0,5}|([a-f0-9]{1,4}:){2}:([a-f0-9]{1,4}:){0,4}|([a-f0-9]{1,4}:){3}:([a-f0-9]{1,4}:){0,3}|([a-f0-9]{1,4}:){4}:([a-f0-9]{1,4}:){0,2}|([a-f0-9]{1,4}:){5}:([a-f0-9]{1,4}:){0,1})([a-f0-9]{1,4}|(((25[0-5])|(2[0-4][0-9])|(1[0-9]{2})|([0-9]{1,2}))\\.){3}((25[0-5])|(2[0-4][0-9])|(1[0-9]{2})|([0-9]{1,2})))$"
    )
    static let ipv6Cidr = ZodRegexPattern(
        pattern:
            "^(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))\\/(12[0-8]|1[01][0-9]|[1-9]?[0-9])$"
    )
    static let base64 = ZodRegexPattern(
        pattern: "^([0-9a-zA-Z+/]{4})*(([0-9a-zA-Z+/]{2}==)|([0-9a-zA-Z+/]{3}=))?$"
    )
    static let base64url = ZodRegexPattern(
        pattern: "^([0-9a-zA-Z-_]{4})*(([0-9a-zA-Z-_]{2}(==)?)|([0-9a-zA-Z-_]{3}(=)?))?$"
    )
    static let nanoid = ZodRegexPattern(pattern: "^[a-zA-Z0-9_-]{21}$")
    static let jwt = ZodRegexPattern(pattern: "^[A-Za-z0-9-_]+\\.[A-Za-z0-9-_]+\\.[A-Za-z0-9-_]*$")
}
