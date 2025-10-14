import Testing
@testable import AISDKProviderUtils

@Suite("Branded Parser")
struct BrandedParserTests {
    @Test("branded string")
    func brandedString() {
        let schema = parseBrandedDef(
            TestZod.branded(TestZod.string())._def as! ZodBrandedDef,
            SchemaTestHelpers.refs()
        )

        SchemaTestHelpers.expect(schema, equals: [
            "type": .string("string")
        ])
    }
}
