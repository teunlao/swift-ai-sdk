import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import SwiftAISDK

@Suite("asArray function tests")
struct AsArrayTests {

    @Test("returns empty array for nil")
    func returnsEmptyArrayForNil() {
        let result: [String] = asArray(nil)
        #expect(result.isEmpty)
    }

    @Test("returns array as-is when value is already an array")
    func returnsArrayAsIs() {
        let input = ["a", "b", "c"]
        let result = asArray(input)
        #expect(result == ["a", "b", "c"])
    }

    @Test("wraps single string in array")
    func wrapsSingleStringInArray() {
        let result = asArray("hello")
        #expect(result == ["hello"])
    }

    @Test("wraps single number in array")
    func wrapsSingleNumberInArray() {
        let result = asArray(42)
        #expect(result == [42])
    }

    @Test("handles empty array")
    func handlesEmptyArray() {
        let input: [String] = []
        let result = asArray(input)
        #expect(result.isEmpty)
    }

    @Test("preserves array with single element")
    func preservesArrayWithSingleElement() {
        let input = [100]
        let result = asArray(input)
        #expect(result == [100])
    }
}
