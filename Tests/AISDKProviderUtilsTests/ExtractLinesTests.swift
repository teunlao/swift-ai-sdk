import Testing
@testable import AISDKProviderUtils

@Suite("extractLines")
struct ExtractLinesTests {
    @Test("returns input unchanged when neither startLine nor endLine is set")
    func returnsInputUnchangedWithoutRange() {
        #expect(extractLines(text: "a\nb\nc") == "a\nb\nc")
    }

    @Test("slices a 1-based inclusive range from a newline file")
    func slicesNewlineRange() {
        #expect(extractLines(text: "a\nb\nc\nd", startLine: 2, endLine: 3) == "b\nc")
    }

    @Test("preserves CRLF line endings")
    func preservesCRLFLineEndings() {
        #expect(extractLines(text: "a\r\nb\r\nc\r\nd", startLine: 2, endLine: 3) == "b\r\nc")
    }

    @Test("preserves CR line endings")
    func preservesCRLineEndings() {
        #expect(extractLines(text: "a\rb\rc\rd", startLine: 2, endLine: 3) == "b\rc")
    }

    @Test("treats endLine past EOF as the last line")
    func treatsEndLinePastEOFAsLastLine() {
        #expect(extractLines(text: "a\nb\nc", startLine: 2, endLine: 99) == "b\nc")
    }

    @Test("defaults startLine to 1 when only endLine is set")
    func defaultsStartLineToOne() {
        #expect(extractLines(text: "a\nb\nc", endLine: 2) == "a\nb")
    }

    @Test("defaults endLine to the last line when only startLine is set")
    func defaultsEndLineToLastLine() {
        #expect(extractLines(text: "a\nb\nc", startLine: 2) == "b\nc")
    }

    @Test("returns input unchanged when there are no line breaks")
    func returnsInputUnchangedForOneLineRange() {
        #expect(extractLines(text: "one-liner", startLine: 1, endLine: 1) == "one-liner")
    }
}
