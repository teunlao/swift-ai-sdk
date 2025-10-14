/**
 Entry point for converting Zod v3 schemas to JSON Schema.

 Port of `@ai-sdk/provider-utils/src/to-json-schema/zod3-to-json-schema/zod3-to-json-schema.ts`.
 */
import Foundation
import AISDKProvider

func zod3ToJSONSchema(
    _ schema: ZodSchema,
    options: Zod3Options? = nil
) -> JSONValue {
    let refs = getRefs(options)

    var definitionsObject: JsonSchemaObject?
    if !refs.options.definitions.isEmpty {
        var collected: JsonSchemaObject = [:]
        for (name, definitionSchema) in refs.options.definitions {
            let definitionRefs = refs.with(
                currentPath: refs.basePath + [refs.definitionPath, name]
            )
            let parsed = parseDef(definitionSchema._def, definitionRefs, true) ?? parseAnyDef()
            collected[name] = .object(parsed)
        }
        definitionsObject = collected
    }

    let effectiveName: String? = refs.options.nameStrategy == .title ? nil : refs.options.name
    let mainRefs = effectiveName == nil
        ? refs
        : refs.with(currentPath: refs.basePath + [refs.definitionPath, effectiveName!])

    var mainSchema = parseDef(schema._def, mainRefs, false) ?? parseAnyDef()

    if refs.options.nameStrategy == .title, let title = refs.options.name {
        mainSchema["title"] = .string(title)
    }

    var combined: JsonSchemaObject

    if let name = effectiveName {
        var definitions = definitionsObject ?? [:]
        definitions[name] = .object(mainSchema)

        let refComponents: [String]
        if refs.refStrategy == .relative {
            refComponents = [refs.definitionPath, name]
        } else {
            refComponents = refs.basePath + [refs.definitionPath, name]
        }

        combined = [
            "$ref": .string(refComponents.joined(separator: "/")),
            refs.definitionPath: .object(definitions)
        ]
    } else {
        combined = mainSchema
        if let definitionsObject {
            combined[refs.definitionPath] = .object(definitionsObject)
        }
    }

    combined["$schema"] = .string("http://json-schema.org/draft-07/schema#")

    return .object(combined)
}
