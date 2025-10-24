import Testing
@testable import AISDKZodAdapter

@Suite("Catch Parser")
struct CatchParserTests {
    @Test("catch pass-through")
    func catchValue() throws {
        let schema = parseCatchDef(
            TestZod.catching(TestZod.number())._def as! ZodCatchDef,
            SchemaTestHelpers.refs()
        )

        SchemaTestHelpers.expect(schema, equals: [
            "type": .string("number")
        ])
    }
}
