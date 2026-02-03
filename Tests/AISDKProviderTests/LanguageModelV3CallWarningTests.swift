import Testing
@testable import AISDKProvider
import Foundation

@Suite("SharedV3Warning")
struct SharedV3WarningTests {

    @Test("SharedV3Warning: unsupported round-trip with details")
    func unsupported_with_details() throws {
        let w = SharedV3Warning.unsupported(feature: "temperature", details: "clamped to [0,1]")
        let data = try JSONEncoder().encode(w)
        let back = try JSONDecoder().decode(SharedV3Warning.self, from: data)
        #expect(back == w)
    }

    @Test("SharedV3Warning: unsupported round-trip without details")
    func unsupported_without_details() throws {
        let w = SharedV3Warning.unsupported(feature: "topK", details: nil)
        let data = try JSONEncoder().encode(w)
        let back = try JSONDecoder().decode(SharedV3Warning.self, from: data)
        #expect(back == w)
    }

    @Test("SharedV3Warning: compatibility round-trip")
    func compatibility_round_trip() throws {
        let w = SharedV3Warning.compatibility(feature: "responseFormat", details: "transformed to json_object")
        let data = try JSONEncoder().encode(w)
        let back = try JSONDecoder().decode(SharedV3Warning.self, from: data)
        #expect(back == w)
    }

    @Test("SharedV3Warning: other message")
    func other_message() throws {
        let w = SharedV3Warning.other(message: "something else")
        let data = try JSONEncoder().encode(w)
        let back = try JSONDecoder().decode(SharedV3Warning.self, from: data)
        #expect(back == w)
    }
}
