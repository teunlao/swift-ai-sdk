import Testing
@testable import AISDKZodAdapter

@Suite("Branded Parser")
struct BrandedParserTests {
    @Test("branded string")
    func brandedString() throws {
        let schema = parseBrandedDef(
            TestZod.branded(TestZod.string())._def as! ZodBrandedDef,
            SchemaTestHelpers.refs()
        )

        SchemaTestHelpers.expect(schema, equals: [
            "type": .string("string")
        ])
    }
}
