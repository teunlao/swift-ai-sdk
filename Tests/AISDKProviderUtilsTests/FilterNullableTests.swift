import Testing
@testable import AISDKProviderUtils

@Suite("filterNullable")
struct FilterNullableTests {
    @Test("removes nil values from a value list")
    func removesNilValuesFromValueList() {
        #expect(filterNullable(1, nil, 2, nil, 3) == [1, 2, 3])
    }

    @Test("preserves other falsy values")
    func preservesOtherFalsyValues() {
        #expect(filterNullable(0, nil, 1) == [0, 1])
        #expect(filterNullable(false, nil, true) == [false, true])
        #expect(filterNullable("", nil, "value") == ["", "value"])
    }

    @Test("filters array input")
    func filtersArrayInput() {
        let values: [String?] = ["a", nil, "b"]
        #expect(filterNullable(values) == ["a", "b"])
    }

    @Test("isNonNullable detects nil and non-nil values")
    func isNonNullableDetectsNilAndNonNilValues() {
        #expect(isNonNullable(1))
        #expect(!isNonNullable(nil as Int?))
    }
}
