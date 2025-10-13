import Testing
import Foundation
@testable import AISDKProvider

@Test func jsonValueCodableRoundTrip() throws {
    let original: JSONValue = [
        "null": .null,
        "bool": .bool(true),
        "num": .number(42.5),
        "str": .string("hello"),
        "arr": .array([.string("a"), .number(1)]),
        "obj": .object(["k": .string("v")])
    ]
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
    #expect(decoded == original)
}
