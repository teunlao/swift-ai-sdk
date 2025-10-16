import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct GenerateObjectOutputSpec<ResultValue: Sendable, PartialValue: Sendable, ElementStream>: Sendable {
    public let kind: GenerateObjectOutputKind
    public let strategy: GenerateObjectOutputStrategy<PartialValue, ResultValue, ElementStream>
    public let schemaName: String?
    public let schemaDescription: String?
    public let mode: GenerateObjectJSONMode?
    public let enumValues: [String]?

    public init(
        kind: GenerateObjectOutputKind,
        strategy: GenerateObjectOutputStrategy<PartialValue, ResultValue, ElementStream>,
        schemaName: String? = nil,
        schemaDescription: String? = nil,
        mode: GenerateObjectJSONMode? = nil,
        enumValues: [String]? = nil
    ) {
        self.kind = kind
        self.strategy = strategy
        self.schemaName = schemaName
        self.schemaDescription = schemaDescription
        self.mode = mode
        self.enumValues = enumValues
    }
}

public enum GenerateObjectOutput {
    public static func object<ObjectResult>(
        schema: FlexibleSchema<ObjectResult>,
        schemaName: String? = nil,
        schemaDescription: String? = nil,
        mode: GenerateObjectJSONMode = .auto
    ) -> GenerateObjectOutputSpec<ObjectResult, [String: JSONValue], Never> {
        GenerateObjectOutputSpec(
            kind: .object,
            strategy: makeObjectOutputStrategy(schema: schema),
            schemaName: schemaName,
            schemaDescription: schemaDescription,
            mode: mode,
            enumValues: nil
        )
    }

    public static func array<ElementResult>(
        schema: FlexibleSchema<ElementResult>,
        schemaName: String? = nil,
        schemaDescription: String? = nil,
        mode: GenerateObjectJSONMode = .auto
    ) -> GenerateObjectOutputSpec<[ElementResult], [ElementResult], AsyncIterableStream<ElementResult>> {
        GenerateObjectOutputSpec(
            kind: .array,
            strategy: makeArrayOutputStrategy(schema: schema),
            schemaName: schemaName,
            schemaDescription: schemaDescription,
            mode: mode,
            enumValues: nil
        )
    }

    public static func enumeration(
        values: [String]
    ) -> GenerateObjectOutputSpec<String, String, Never> {
        GenerateObjectOutputSpec(
            kind: .enumeration,
            strategy: makeEnumOutputStrategy(values: values),
            schemaName: nil,
            schemaDescription: nil,
            mode: .json,
            enumValues: values
        )
    }

    public static func noSchema() -> GenerateObjectOutputSpec<JSONValue, JSONValue, Never> {
        GenerateObjectOutputSpec(
            kind: .noSchema,
            strategy: makeNoSchemaOutputStrategy(),
            schemaName: nil,
            schemaDescription: nil,
            mode: nil,
            enumValues: nil
        )
    }
}
