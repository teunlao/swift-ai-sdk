/**
 Core parsing logic for converting Zod definitions into JSON Schema.

 Port of `@ai-sdk/provider-utils/src/to-json-schema/zod3-to-json-schema/parse-def.ts`
 and `select-parser.ts`.
 */
import Foundation
import AISDKProvider

enum ParserResult {
    case schema(JsonSchemaObject?)
    case getter(() -> ZodTypeDef)
    case none
}

func parseDef(
    _ def: ZodTypeDef,
    _ refs: Refs,
    _ forceResolution: Bool = false
) -> JsonSchemaObject? {
    let seenItem = refs[def]

    if let override = refs.override {
        let overrideResult = override(def, refs, seenItem, forceResolution)
        switch overrideResult {
        case .useDefault:
            break
        case .schema(let schema):
            if var item = seenItem {
                item.jsonSchema = schema
                refs.seenRegistry[def] = item
            }
            return schema
        }
    }

    if let seenItem, !forceResolution {
        if let seenSchema = getRef(from: seenItem, refs: refs) {
            return seenSchema
        }
    }

    var newSeen = Seen(def: def, path: refs.currentPath, jsonSchema: nil)
    refs.seenRegistry[def] = newSeen

    let parserResult = selectParser(def, refs)
    let jsonSchema: JsonSchemaObject?

    switch parserResult {
    case .schema(let schema):
        jsonSchema = schema
    case .getter(let getter):
        jsonSchema = parseDef(getter(), refs, false)
    case .none:
        jsonSchema = nil
    }

    var processedSchema = jsonSchema
    if var schema = processedSchema {
        addMeta(def: def, refs: refs, schema: &schema)
        processedSchema = schema
    }

    if let postProcess = refs.postProcess {
        processedSchema = postProcess(processedSchema, def, refs)
    }

    newSeen.jsonSchema = processedSchema
    refs.seenRegistry[def] = newSeen

    return processedSchema
}

private func getRef(from item: Seen, refs: Refs) -> JsonSchemaObject? {
    switch refs.refStrategy {
    case .root:
        return ["$ref": .string(item.path.joined(separator: "/"))]
    case .relative:
        return ["$ref": .string(getRelativePath(refs.currentPath, item.path))]
    case .none:
        return nil
    case .seen:
        if item.path.count < refs.currentPath.count && zip(item.path, refs.currentPath).allSatisfy({ $0 == $1 }) {
            print("Recursive reference detected at \(refs.currentPath.joined(separator: "/"))! Defaulting to any.")
            return parseAnyDef()
        }
        return parseAnyDef()
    }
}

private func addMeta(def: ZodTypeDef, refs: Refs, schema: inout JsonSchemaObject) {
    if let description = def.description {
        schema["description"] = .string(description)
    }
}

private func selectParser(_ def: ZodTypeDef, _ refs: Refs) -> ParserResult {
    switch def.typeName {
    case .zodString:
        return .schema(parseStringDef(def as! ZodStringDef, refs))
    case .zodNumber:
        return .schema(parseNumberDef(def as! ZodNumberDef))
    case .zodObject:
        return .schema(parseObjectDef(def as! ZodObjectDef, refs))
    case .zodBigInt:
        return .schema(parseBigintDef(def as! ZodBigIntDef))
    case .zodBoolean:
        return .schema(parseBooleanDef())
    case .zodDate:
        return .schema(parseDateDef(def as! ZodDateDef, refs))
    case .zodUndefined:
        return .schema(parseUndefinedDef())
    case .zodNull:
        return .schema(parseNullDef())
    case .zodArray:
        return .schema(parseArrayDef(def as! ZodArrayDef, refs))
    case .zodUnion, .zodDiscriminatedUnion:
        return .schema(parseUnionDef(def as! ZodUnionBaseDef, refs))
    case .zodIntersection:
        return .schema(parseIntersectionDef(def as! ZodIntersectionDef, refs))
    case .zodTuple:
        return .schema(parseTupleDef(def as! ZodTupleDef, refs))
    case .zodRecord:
        return .schema(parseRecordDef(def as! ZodRecordDef, refs))
    case .zodLiteral:
        return .schema(parseLiteralDef(def as! ZodLiteralDef))
    case .zodEnum:
        return .schema(parseEnumDef(def as! ZodEnumDef))
    case .zodNativeEnum:
        return .schema(parseNativeEnumDef(def as! ZodNativeEnumDef))
    case .zodNullable:
        return .schema(parseNullableDef(def as! ZodNullableDef, refs))
    case .zodOptional:
        return .schema(parseOptionalDef(def as! ZodOptionalDef, refs))
    case .zodMap:
        return .schema(parseMapDef(def as! ZodMapDef, refs))
    case .zodSet:
        return .schema(parseSetDef(def as! ZodSetDef, refs))
    case .zodLazy:
        let lazyDef = def as! ZodLazyDef
        return .getter { lazyDef.getter()._def }
    case .zodPromise:
        return .schema(parsePromiseDef(def as! ZodPromiseDef, refs))
    case .zodNever, .zodNaN:
        return .schema(parseNeverDef())
    case .zodEffects:
        return .schema(parseEffectsDef(def as! ZodEffectsDef, refs))
    case .zodAny:
        return .schema(parseAnyDef())
    case .zodUnknown:
        return .schema(parseUnknownDef())
    case .zodDefault:
        return .schema(parseDefaultDef(def as! ZodDefaultDef, refs))
    case .zodBranded:
        return .schema(parseBrandedDef(def as! ZodBrandedDef, refs))
    case .zodReadonly:
        return .schema(parseReadonlyDef(def as! ZodReadonlyDef, refs))
    case .zodCatch:
        return .schema(parseCatchDef(def as! ZodCatchDef, refs))
    case .zodPipeline:
        return .schema(parsePipelineDef(def as! ZodPipelineDef, refs))
    case .zodFunction, .zodVoid, .zodSymbol:
        return .none
    }
}

private func getRelativePath(_ from: [String], _ to: [String]) -> String {
    var index = 0
    while index < from.count && index < to.count && from[index] == to[index] {
        index += 1
    }

    let upward = String(from.count - index)
    let remaining = to[index...]
    return ([upward] + remaining).joined(separator: "/")
}
