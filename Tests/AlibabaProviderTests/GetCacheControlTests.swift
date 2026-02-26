import Testing
@testable import AISDKProvider
@testable import AlibabaProvider

@Suite("CacheControlValidator")
struct GetCacheControlTests {
    @Test("extracts cacheControl from provider metadata")
    func extractsCacheControl() {
        let validator = CacheControlValidator()

        let result = validator.getCacheControl([
            "alibaba": [
                "cacheControl": .object(["type": .string("ephemeral")])
            ]
        ])

        #expect(result == .object(["type": .string("ephemeral")]))
    }

    @Test("warns when exceeding 4 cache breakpoints")
    func warnsWhenExceedingLimit() {
        let validator = CacheControlValidator()

        for _ in 0..<4 {
            _ = validator.getCacheControl([
                "alibaba": ["cacheControl": .object(["type": .string("ephemeral")])]
            ])
        }

        let result = validator.getCacheControl([
            "alibaba": ["cacheControl": .object(["type": .string("ephemeral")])]
        ])

        #expect(result == .object(["type": .string("ephemeral")]))
        #expect(validator.getWarnings().count == 1)
        #expect(validator.getWarnings().first == .other(
            message: "Max breakpoint limit exceeded. Only the last 4 cache markers will take effect."
        ))
    }

    @Test("returns nil when no cache control is present")
    func returnsNilWhenMissing() {
        let validator = CacheControlValidator()
        let result = validator.getCacheControl(["alibaba": [:]])
        #expect(result == nil)
    }
}

