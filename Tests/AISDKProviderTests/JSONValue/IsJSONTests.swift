import Foundation
import Testing
@testable import AISDKProvider

@Test func jsonTypeAliasesInterop() {
    let object: JSONObject = [
        "key": .string("value"),
        "nested": .object(["inner": .number(1)])
    ]
    #expect(isJSONObject(object))

    let array: JSONArray = [
        .string("entry"),
        .object(["flag": .bool(true)]),
        .null
    ]
    #expect(isJSONArray(array))
}

@Test func isJSONValueAcceptsPrimitiveAndNull() {
    #expect(isJSONValue(nil))
    #expect(isJSONValue(NSNull()))
    #expect(isJSONValue("string"))
    #expect(isJSONValue(42))
    #expect(isJSONValue(Double.pi))
    #expect(isJSONValue(true))
    #expect(isJSONValue(NSNumber(value: 7)))
    #expect(isJSONValue(JSONValue.null))
    #expect(isJSONValue(JSONValue.bool(false)))
    #expect(isJSONValue(JSONValue.number(3.5)))
    #expect(isJSONValue(JSONValue.string("value")))
}

@Test func isJSONValueAcceptsNestedCollections() {
    let nestedArray: [Any] = [
        "text",
        1,
        ["inner": ["a": 1]],
        [JSONValue.bool(true)]
    ]
    #expect(isJSONValue(nestedArray))

    let jsonArray: JSONValue = [
        .string("a"),
        .array([.number(1)]),
        .object(["key": .null])
    ]
    #expect(isJSONValue(jsonArray))

    let foundationArray: NSArray = [
        "value",
        ["nested": ["key": "value"]]
    ]
    #expect(isJSONValue(foundationArray))
}

@Test func isJSONValueRejectsUnsupportedTypes() {
    #expect(!isJSONValue(Date()))
    #expect(!isJSONValue(URL(string: "https://example.com")!))
    #expect(!isJSONValue(Set([1, 2, 3])))
    #expect(!isJSONValue(Data()))

    let invalidDictionary: [String: Any] = [
        "allowed": "value",
        "invalid": Date()
    ]
    #expect(!isJSONValue(invalidDictionary))
}

@Test func isJSONArrayValidatesAllElements() {
    #expect(isJSONArray([1, "two", JSONValue.null]))

    let jsonValueArray = JSONValue.array([.number(1), .string("two"), .null])
    #expect(isJSONArray(jsonValueArray))

    let foundationArray: NSArray = [1, NSNull(), ["key": "value"]]
    #expect(isJSONArray(foundationArray))

    #expect(!isJSONArray(1))
    #expect(!isJSONArray(["valid", Date()]))

    let invalidFoundationArray: NSArray = [1, Date()]
    #expect(!isJSONArray(invalidFoundationArray))
}

@Test func isJSONObjectValidatesEntries() {
    #expect(isJSONObject(["key": "value", "nested": ["inner": 1]]))

    let jsonValueObject = JSONValue.object([
        "array": .array([.string("a")]),
        "null": .null
    ])
    #expect(isJSONObject(jsonValueObject))

    let foundationDictionary: NSDictionary = [
        "number": 1,
        "nested": ["inner": "value"],
        "null": NSNull()
    ]
    #expect(isJSONObject(foundationDictionary))

    #expect(!isJSONObject(nil))
    #expect(!isJSONObject(["invalid": Date()]))

    let nonStringKeyDictionary = NSMutableDictionary()
    nonStringKeyDictionary[NSNumber(value: 1)] = "value"
    #expect(!isJSONObject(nonStringKeyDictionary))
}
