import Testing
import AISDKProvider
import SwiftAISDK

@Suite("Data URL text decoding")
struct DataURLTests {
    @Test(arguments: [
        ("data:text/plain;charset=utf-8;base64,Y2Fmw6k=", "café"),
        ("data:text/plain; charset=\"UTF-8\";base64,8J+Zgg==", "🙂"),
        ("data:text/plain;charset=iso-8859-1;base64,Y2Fm6Q==", "café"),
        ("data:text/plain;charset=windows-1252;base64,gIH/", "€\u{81}ÿ"),
        ("data:text/plain;base64,w6k=", "\u{00C3}\u{00A9}")
    ])
    func decodesText(input: String, expected: String) throws {
        #expect(try getTextFromDataUrl(input) == expected)
    }

    @Test(arguments: ["not-a-data-url", "data:text/plain;base64,invalid-base64", "data:text/plain;base64,aG\u{A0}k="])
    func rejectsMalformedData(input: String) {
        #expect(throws: InvalidArgumentError.self) { try getTextFromDataUrl(input) }
    }
}
