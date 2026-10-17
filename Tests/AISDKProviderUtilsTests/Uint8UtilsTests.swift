import Foundation
import Testing
import AISDKProviderUtils

@Suite("Base64 decoding")
struct Uint8UtilsTests {
    @Test(arguments: ["AA===", "===="])
    func malformedPaddingIsRejected(text: String) {
        #expect(throws: DecodingError.self) { try convertBase64ToData(text) }
    }
}
