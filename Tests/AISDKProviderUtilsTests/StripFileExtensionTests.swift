import Testing
@testable import AISDKProviderUtils

@Suite("stripFileExtension")
struct StripFileExtensionTests {
    @Test("strips the extension from a filename")
    func stripsExtension() {
        #expect(stripFileExtension("report.pdf") == "report")
    }

    @Test("returns the input when there is no extension")
    func returnsInputWithoutExtension() {
        #expect(stripFileExtension("report") == "report")
    }

    @Test("strips all extension segments for multi-dot filenames")
    func stripsMultiDotFilename() {
        #expect(stripFileExtension("archive.tar.gz") == "archive")
    }

    @Test("strips a trailing dot")
    func stripsTrailingDot() {
        #expect(stripFileExtension("report.") == "report")
    }

    @Test("matches upstream first-dot behavior for hidden files")
    func stripsFromLeadingDot() {
        #expect(stripFileExtension(".env") == "")
    }
}
