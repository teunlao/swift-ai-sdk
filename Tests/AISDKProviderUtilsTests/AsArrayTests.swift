import Testing

@testable import AISDKProviderUtils

@Suite("asArray")
struct ProviderUtilsAsArrayTests {
    @Test("returns empty array for nil")
    func returnsEmptyArrayForNil() {
        let value: String? = nil

        #expect(asArray(value).isEmpty)
    }

    @Test("wraps a single value in an array")
    func wrapsSingleValueInArray() {
        #expect(asArray("value") == ["value"])
    }

    @Test("returns array value unchanged")
    func returnsArrayValueUnchanged() {
        let value = ["a", "b"]

        #expect(asArray(value) == value)
    }
}
