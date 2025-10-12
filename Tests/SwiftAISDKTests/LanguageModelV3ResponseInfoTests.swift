import Testing
@testable import SwiftAISDK
import Foundation

@Test("ResponseInfo: flat fields accessible (no nested metadata)")
func v3_responseInfo_flat_fields() throws {
    let ts = ISO8601DateFormatter().date(from: "2025-10-12T00:00:00Z")
    let info = LanguageModelV3ResponseInfo(
        id: "resp-1",
        timestamp: ts,
        modelId: "gpt-xyz",
        headers: ["x": "y"],
        body: ["ok": .bool(true)]
    )
    #expect(info.id == "resp-1")
    #expect(info.modelId == "gpt-xyz")
    #expect(info.timestamp == ts)
    #expect(info.headers?["x"] == "y")
    if case .object(let obj)? = info.body, case .bool(true)? = obj["ok"] { /* ok */ } else { #expect(Bool(false)) }
}
