import Testing
@testable import AISDKProvider
import Foundation

@Test("ResponseInfo: flat fields accessible (no nested metadata)")
func v3_responseInfo_flat_fields() throws {
    let ts = ISO8601DateFormatter().date(from: "2025-10-12T00:00:00Z")
    let info = LanguageModelV3ResponseInfo(
        id: "resp-1",
        timestamp: ts,
        modelId: "gpt-xyz",
        headers: ["x": "y"],
        body: ["ok": JSONValue.bool(true)] as [String: JSONValue]
    )
    #expect(info.id == "resp-1")
    #expect(info.modelId == "gpt-xyz")
    #expect(info.timestamp == ts)
    #expect(info.headers?["x"] == "y")
    if let bodyDict = info.body as? [String: JSONValue],
       case .object(let obj) = JSONValue.object(bodyDict),
       case .bool(true) = obj["ok"] {
        // ok
    } else {
        #expect(Bool(false), "Expected body to contain ok=true")
    }
}
