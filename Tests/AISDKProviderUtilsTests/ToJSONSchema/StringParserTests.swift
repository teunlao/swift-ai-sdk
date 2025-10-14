import Testing

@testable import AISDKProviderUtils

@Suite("String Parser")
struct StringParserTests {
    @Test("minimum length")
    func minimumLength() {
        let schema = parseStringDef(
            TestZod.string([.min(value: 5, message: nil)])._def as! ZodStringDef,
            SchemaTestHelpers.refs()
        )

        SchemaTestHelpers.expect(
            schema,
            equals: [
                "type": .string("string"),
                "minLength": .number(5),
            ])
    }

    @Test("maximum length")
    func maximumLength() {
        let schema = parseStringDef(
            TestZod.string([.max(value: 5, message: nil)])._def as! ZodStringDef,
            SchemaTestHelpers.refs()
        )

        SchemaTestHelpers.expect(
            schema,
            equals: [
                "type": .string("string"),
                "maxLength": .number(5),
            ])
    }

    @Test("length range")
    func lengthRange() {
        let def = TestZod.string([
            .min(value: 5, message: nil),
            .max(value: 5, message: nil),
        ])
        let schema = parseStringDef(def._def as! ZodStringDef, SchemaTestHelpers.refs())

        SchemaTestHelpers.expect(
            schema,
            equals: [
                "type": .string("string"),
                "minLength": .number(5),
                "maxLength": .number(5),
            ])
    }

    @Test("email format")
    func email() {
        let schema = parseStringDef(
            TestZod.string([.email(message: nil)])._def as! ZodStringDef,
            SchemaTestHelpers.refs()
        )

        SchemaTestHelpers.expect(
            schema,
            equals: [
                "type": .string("string"),
                "format": .string("email"),
            ])
    }

    @Test("uuid format")
    func uuid() {
        let schema = parseStringDef(
            TestZod.string([.uuid(message: nil)])._def as! ZodStringDef,
            SchemaTestHelpers.refs()
        )

        SchemaTestHelpers.expect(
            schema,
            equals: [
                "type": .string("string"),
                "format": .string("uuid"),
            ])
    }

    @Test("url format")
    func url() {
        let schema = parseStringDef(
            TestZod.string([.url(message: nil)])._def as! ZodStringDef,
            SchemaTestHelpers.refs()
        )

        SchemaTestHelpers.expect(
            schema,
            equals: [
                "type": .string("string"),
                "format": .string("uri"),
            ])
    }

    @Test("regex constraint")
    func regex() {
        let schema = parseStringDef(
            TestZod.string([
                .regex(pattern: ZodRegexPattern(pattern: "[A-C]"), message: nil)
            ])._def as! ZodStringDef,
            SchemaTestHelpers.refs()
        )

        SchemaTestHelpers.expect(
            schema,
            equals: [
                "type": .string("string"),
                "pattern": .string("[A-C]"),
            ])
    }

    @Test("cuid constraint")
    func cuid() {
        let schema = parseStringDef(
            TestZod.string([.cuid(message: nil)])._def as! ZodStringDef,
            SchemaTestHelpers.refs()
        )

        SchemaTestHelpers.expect(
            schema,
            equals: [
                "type": .string("string"),
                "pattern": .string(ZodPatterns.cuid.pattern),
            ])
    }

    @Test("cuid2 constraint")
    func cuid2() {
        let schema = parseStringDef(
            TestZod.string([.cuid2(message: nil)])._def as! ZodStringDef,
            SchemaTestHelpers.refs()
        )

        SchemaTestHelpers.expect(
            schema,
            equals: [
                "type": .string("string"),
                "pattern": .string(ZodPatterns.cuid2.pattern),
            ])
    }

    @Test("datetime constraint")
    func datetime() {
        let schema = parseStringDef(
            TestZod.string([.datetime(message: nil)])._def as! ZodStringDef,
            SchemaTestHelpers.refs()
        )

        SchemaTestHelpers.expect(
            schema,
            equals: [
                "type": .string("string"),
                "format": .string("date-time"),
            ])
    }

    @Test("date constraint")
    func date() {
        let schema = parseStringDef(
            TestZod.string([.date(message: nil)])._def as! ZodStringDef,
            SchemaTestHelpers.refs()
        )

        SchemaTestHelpers.expect(
            schema,
            equals: [
                "type": .string("string"),
                "format": .string("date"),
            ])
    }

    @Test("time constraint")
    func time() {
        let schema = parseStringDef(
            TestZod.string([.time(message: nil)])._def as! ZodStringDef,
            SchemaTestHelpers.refs()
        )

        SchemaTestHelpers.expect(
            schema,
            equals: [
                "type": .string("string"),
                "format": .string("time"),
            ])
    }

    @Test("duration constraint")
    func duration() {
        let schema = parseStringDef(
            TestZod.string([.duration(message: nil)])._def as! ZodStringDef,
            SchemaTestHelpers.refs()
        )

        SchemaTestHelpers.expect(
            schema,
            equals: [
                "type": .string("string"),
                "format": .string("duration"),
            ])
    }

    @Test("length constraint")
    func length() {
        let schema = parseStringDef(
            TestZod.string([.length(value: 15, message: nil)])._def as! ZodStringDef,
            SchemaTestHelpers.refs()
        )

        SchemaTestHelpers.expect(
            schema,
            equals: [
                "type": .string("string"),
                "minLength": .number(15),
                "maxLength": .number(15),
            ])
    }

    @Test("startsWith check")
    func startsWith() {
        let schema = parseStringDef(
            TestZod.string([
                .startsWith(value: "aBcD123{}[]", message: nil)
            ])._def as! ZodStringDef,
            SchemaTestHelpers.refs()
        )

        SchemaTestHelpers.expect(
            schema,
            equals: [
                "type": .string("string"),
                "pattern": .string("^aBcD123\\{\\}\\[\\]"),
            ])
    }

    @Test("endsWith check")
    func endsWith() {
        let schema = parseStringDef(
            TestZod.string([
                .endsWith(value: "aBcD123{}[]", message: nil)
            ])._def as! ZodStringDef,
            SchemaTestHelpers.refs()
        )

        SchemaTestHelpers.expect(
            schema,
            equals: [
                "type": .string("string"),
                "pattern": .string("aBcD123\\{\\}\\[\\]$"),
            ])
    }

    @Test("includes check")
    func includes() {
        let schema = parseStringDef(
            TestZod.string([
                .includes(value: "aBcD123{}[]", message: nil)
            ])._def as! ZodStringDef,
            SchemaTestHelpers.refs()
        )

        SchemaTestHelpers.expect(
            schema,
            equals: [
                "type": .string("string"),
                "pattern": .string("aBcD123\\{\\}\\[\\]"),
            ])
    }

    @Test("pattern strategy preserve")
    func patternStrategyPreserve() {
        let schema = parseStringDef(
            TestZod.string([
                .includes(value: "aBcD123{}[]", message: nil)
            ])._def as! ZodStringDef,
            SchemaTestHelpers.refs(PartialOptions(patternStrategy: .preserve))
        )

        SchemaTestHelpers.expect(
            schema,
            equals: [
                "type": .string("string"),
                "pattern": .string("aBcD123{}[]"),
            ])
    }

    @Test("multiple pattern checks use allOf")
    func multiplePatternChecks() {
        let schema = parseStringDef(
            TestZod.string([
                .startsWith(value: "alpha", message: nil),
                .endsWith(value: "omega", message: nil),
            ])._def as! ZodStringDef,
            SchemaTestHelpers.refs()
        )

        SchemaTestHelpers.expect(
            schema,
            equals: [
                "type": .string("string"),
                "allOf": .array([
                    .object(["pattern": .string("^alpha")]),
                    .object(["pattern": .string("omega$")]),
                ]),
            ])
    }

    @Test("multiple min/max picks extreme values")
    func multipleMinMax() {
        let schema = parseStringDef(
            TestZod.string([
                .min(value: 1, message: nil),
                .min(value: 2, message: nil),
                .max(value: 3, message: nil),
                .max(value: 4, message: nil),
            ])._def as! ZodStringDef,
            SchemaTestHelpers.refs()
        )

        SchemaTestHelpers.expect(
            schema,
            equals: [
                "type": .string("string"),
                "minLength": .number(2),
                "maxLength": .number(3),
            ])
    }

    @Test("multiple formats result in anyOf")
    func multipleFormats() {
        let schema = parseStringDef(
            TestZod.string([
                .ip(version: .v4AndV6, message: nil),
                .email(message: nil),
            ])._def as! ZodStringDef,
            SchemaTestHelpers.refs()
        )

        SchemaTestHelpers.expect(
            schema,
            equals: [
                "type": .string("string"),
                "anyOf": .array([
                    .object(["format": .string("ipv4")]),
                    .object(["format": .string("ipv6")]),
                    .object(["format": .string("email")]),
                ]),
            ])
    }

    @Test("base64 strategies")
    func base64Strategies() {
        let def = TestZod.string([.base64(message: nil)])._def as! ZodStringDef

        let defaultSchema = parseStringDef(def, SchemaTestHelpers.refs())
        SchemaTestHelpers.expect(
            defaultSchema,
            equals: [
                "type": .string("string"),
                "contentEncoding": .string("base64"),
            ])

        let contentEncoding = parseStringDef(
            def,
            SchemaTestHelpers.refs(PartialOptions(base64Strategy: .contentEncodingBase64))
        )
        SchemaTestHelpers.expect(
            contentEncoding,
            equals: [
                "type": .string("string"),
                "contentEncoding": .string("base64"),
            ])

        let formatBinary = parseStringDef(
            def,
            SchemaTestHelpers.refs(PartialOptions(base64Strategy: .formatBinary))
        )
        SchemaTestHelpers.expect(
            formatBinary,
            equals: [
                "type": .string("string"),
                "format": .string("binary"),
            ])

        let pattern = parseStringDef(
            def,
            SchemaTestHelpers.refs(PartialOptions(base64Strategy: .patternZod))
        )
        SchemaTestHelpers.expect(
            pattern,
            equals: [
                "type": .string("string"),
                "pattern": .string(ZodPatterns.base64.pattern),
            ])
    }

    @Test("nanoid pattern")
    func nanoid() {
        let schema = parseStringDef(
            TestZod.string([.nanoid(message: nil)])._def as! ZodStringDef,
            SchemaTestHelpers.refs()
        )

        SchemaTestHelpers.expect(
            schema,
            equals: [
                "type": .string("string"),
                "pattern": .string(ZodPatterns.nanoid.pattern),
            ])
    }

    @Test("ulid pattern")
    func ulid() {
        let schema = parseStringDef(
            TestZod.string([.ulid(message: nil)])._def as! ZodStringDef,
            SchemaTestHelpers.refs()
        )

        SchemaTestHelpers.expect(
            schema,
            equals: [
                "type": .string("string"),
                "pattern": .string(ZodPatterns.ulid.pattern),
            ])
    }

    @Test("email strategies")
    func emailStrategies() {
        let def = TestZod.string([.email(message: nil)])._def as! ZodStringDef

        let defaultSchema = parseStringDef(def, SchemaTestHelpers.refs())
        SchemaTestHelpers.expect(
            defaultSchema,
            equals: [
                "type": .string("string"),
                "format": .string("email"),
            ])

        let idn = parseStringDef(
            def, SchemaTestHelpers.refs(PartialOptions(emailStrategy: .formatIdnEmail)))
        SchemaTestHelpers.expect(
            idn,
            equals: [
                "type": .string("string"),
                "format": .string("idn-email"),
            ])

        let pattern = parseStringDef(
            def, SchemaTestHelpers.refs(PartialOptions(emailStrategy: .patternZod)))
        SchemaTestHelpers.expect(
            pattern,
            equals: [
                "type": .string("string"),
                "pattern": .string(ZodPatterns.email.pattern),
            ])
    }

    @Test("regex flag conversion")
    func regexFlagConversion() {
        let base = TestZod.string([
            .regex(pattern: ZodRegexPattern(pattern: "(^|\\^foo)Ba[r-z]+."), message: nil)
        ])
        let baseSchema = parseStringDef(
            base._def as! ZodStringDef,
            SchemaTestHelpers.refs(PartialOptions(applyRegexFlags: true)))
        SchemaTestHelpers.expect(
            baseSchema,
            equals: [
                "type": .string("string"),
                "pattern": .string("(^|\\^foo)Ba[r-z]+."),
            ])

        let ignoreCase = TestZod.string([
            .regex(
                pattern: ZodRegexPattern(pattern: "(^|\\^foo)Ba[r-z]+.", flags: "i"), message: nil)
        ])
        let ignoreCaseSchema = parseStringDef(
            ignoreCase._def as! ZodStringDef,
            SchemaTestHelpers.refs(PartialOptions(applyRegexFlags: true)))
        SchemaTestHelpers.expect(
            ignoreCaseSchema,
            equals: [
                "type": .string("string"),
                "pattern": .string("(^|\\^[fF][oO][oO])[bB][aA][r-zR-Z]+."),
            ])

        let multilineDotAll = TestZod.string([
            .regex(
                pattern: ZodRegexPattern(pattern: "(^|\\^foo)Ba[r-z]+.", flags: "ms"), message: nil)
        ])
        let multilineDotAllSchema = parseStringDef(
            multilineDotAll._def as! ZodStringDef,
            SchemaTestHelpers.refs(PartialOptions(applyRegexFlags: true)))
        SchemaTestHelpers.expect(
            multilineDotAllSchema,
            equals: [
                "type": .string("string"),
                "pattern": .string("((^|(?<=[\\r\\n]))|\\^foo)Ba[r-z]+[.\\r\\n]"),
            ])

        let allFlags = TestZod.string([
            .regex(
                pattern: ZodRegexPattern(pattern: "(^|\\^foo)Ba[r-z]+.", flags: "ims"), message: nil
            )
        ])
        let allFlagsSchema = parseStringDef(
            allFlags._def as! ZodStringDef,
            SchemaTestHelpers.refs(PartialOptions(applyRegexFlags: true)))
        SchemaTestHelpers.expect(
            allFlagsSchema,
            equals: [
                "type": .string("string"),
                "pattern": .string("((^|(?<=[\\r\\n]))|\\^[fF][oO][oO])[bB][aA][r-zR-Z]+[.\\r\\n]"),
            ])

        let multiline = TestZod.string([
            .regex(pattern: ZodRegexPattern(pattern: "foo.+$", flags: "m"), message: nil)
        ])
        let multilineSchema = parseStringDef(
            multiline._def as! ZodStringDef,
            SchemaTestHelpers.refs(PartialOptions(applyRegexFlags: true)))
        SchemaTestHelpers.expect(
            multilineSchema,
            equals: [
                "type": .string("string"),
                "pattern": .string("foo.+($|(?=[\\r\\n]))"),
            ])

        let caseInsensitiveRange = TestZod.string([
            .regex(pattern: ZodRegexPattern(pattern: "foo.+[amz]", flags: "i"), message: nil)
        ])
        let caseInsensitiveRangeSchema = parseStringDef(
            caseInsensitiveRange._def as! ZodStringDef,
            SchemaTestHelpers.refs(PartialOptions(applyRegexFlags: true)))
        SchemaTestHelpers.expect(
            caseInsensitiveRangeSchema,
            equals: [
                "type": .string("string"),
                "pattern": .string("[fF][oO][oO].+[aAmMzZ]"),
            ])
    }
}
