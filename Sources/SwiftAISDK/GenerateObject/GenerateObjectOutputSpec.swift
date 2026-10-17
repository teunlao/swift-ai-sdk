import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct GenerateObjectOutputSpec<ResultValue: Sendable, PartialValue: Sendable, ElementStream>: Sendable {
    public let kind: GenerateObjectOutputKind
    public let strategy: GenerateObjectOutputStrategy<PartialValue, ResultValue, ElementStream>
    public let schemaName: String?
    public let schemaDescription: String?
    public let enumValues: [String]?

    public init(
        kind: GenerateObjectOutputKind,
        strategy: GenerateObjectOutputStrategy<PartialValue, ResultValue, ElementStream>,
        schemaName: String? = nil,
        schemaDescription: String? = nil,
        enumValues: [String]? = nil
    ) {
        self.kind = kind
        self.strategy = strategy
        self.schemaName = schemaName
        self.schemaDescription = schemaDescription
        self.enumValues = enumValues
    }
}

public enum GenerateObjectOutput {
    public static func object<ObjectResult>(
        schema: FlexibleSchema<ObjectResult>,
        schemaName: String? = nil,
        schemaDescription: String? = nil
    ) -> GenerateObjectOutputSpec<ObjectResult, [String: JSONValue], Never> {
        GenerateObjectOutputSpec(
            kind: .object,
            strategy: makeObjectOutputStrategy(schema: schema),
            schemaName: schemaName,
            schemaDescription: schemaDescription,
            enumValues: nil
        )
    }

    public static func array<ElementResult>(
        schema: FlexibleSchema<ElementResult>,
        schemaName: String? = nil,
        schemaDescription: String? = nil
    ) -> GenerateObjectOutputSpec<[ElementResult], [ElementResult], AsyncIterableStream<ElementResult>> {
        GenerateObjectOutputSpec(
            kind: .array,
            strategy: makeArrayOutputStrategy(schema: schema),
            schemaName: schemaName,
            schemaDescription: schemaDescription,
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
            enumValues: values
        )
    }

    public static func noSchema() -> GenerateObjectOutputSpec<JSONValue, JSONValue, Never> {
        GenerateObjectOutputSpec(
            kind: .noSchema,
            strategy: makeNoSchemaOutputStrategy(),
            schemaName: nil,
            schemaDescription: nil,
            enumValues: nil
        )
    }
}
