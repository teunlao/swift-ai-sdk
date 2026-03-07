import Foundation
import Testing
@testable import SwiftAISDK

@Suite("convertFileListToFileUIParts")
struct ConvertFileListToFileUIPartsTests {
    @Test("returns empty array for nil input")
    func returnsEmptyArrayForNilInput() async throws {
        let parts = try await convertFileListToFileUIParts(files: nil)

        #expect(parts.isEmpty)
    }

    @Test("converts file URL to file UI part with data URL")
    func convertsFileURLToFileUIPart() async throws {
        let fileURL = try makeTemporaryFile(
            named: "greeting.txt",
            data: Data("Hello".utf8)
        )
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let parts = try await convertFileListToFileUIParts(files: [fileURL])

        #expect(parts.count == 1)
        #expect(parts[0].mediaType == "text/plain")
        #expect(parts[0].filename == "greeting.txt")
        #expect(parts[0].url == "data:text/plain;base64,SGVsbG8=")
    }

    @Test("falls back to application/octet-stream when type cannot be inferred")
    func fallsBackToOctetStreamForUnknownFiles() async throws {
        let fileURL = try makeTemporaryFile(
            named: "blob",
            data: Data([0x00, 0x01, 0x02, 0x03])
        )
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let parts = try await convertFileListToFileUIParts(files: [fileURL])

        #expect(parts.count == 1)
        #expect(parts[0].mediaType == "application/octet-stream")
        #expect(parts[0].url == "data:application/octet-stream;base64,AAECAw==")
    }

    @Test("throws for non-file URLs")
    func throwsForNonFileURLs() async throws {
        do {
            _ = try await convertFileListToFileUIParts(
                files: [try #require(URL(string: "https://example.com/file.txt"))]
            )
            Issue.record("Expected convertFileListToFileUIParts to throw for non-file URLs")
        } catch {
            #expect(error.localizedDescription == "Only file URLs are supported in the current environment")
        }
    }
}

private func makeTemporaryFile(named name: String, data: Data) throws -> URL {
    let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)

    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

    let fileURL = directoryURL.appendingPathComponent(name)
    try data.write(to: fileURL)
    return fileURL
}
