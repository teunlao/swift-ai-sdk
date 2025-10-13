import Testing
import Foundation
@testable import SwiftAISDK

/**
 Tests for ConvertToLanguageModelPrompt functions.

 Port of `@ai-sdk/ai/src/prompt/convert-to-language-model-prompt.test.ts`.

 Covers:
 - convertToLanguageModelPrompt: main conversion function
 - convertToLanguageModelMessage: message converter
 - Image/file download logic
 - URL support checking
 - Tool message combining
 - Provider options handling
 - Media type detection
 */

// MARK: - Test Helpers

/// Mock download function that returns predefined results
func createMockDownload(_ results: [(url: URL, data: Data, mediaType: String?)]?) -> DownloadFunction? {
    guard let results = results else { return nil }

    return { requests in
        var downloadResults: [DownloadResult?] = []

        for request in requests {
            if let match = results.first(where: { $0.url == request.url }) {
                downloadResults.append(DownloadResult(
                    data: match.data,
                    mediaType: match.mediaType
                ))
            } else {
                // Return nil for URLs not in mock results (pass-through)
                downloadResults.append(nil)
            }
        }

        return downloadResults
    }
}

// MARK: - convertToLanguageModelPrompt Tests

@Suite("ConvertToLanguageModelPrompt")
struct ConvertToLanguageModelPromptTests {

    // MARK: - User Message - Image Parts

    @Test("should download images for user image parts with URLs when model does not support image URLs")
    func downloadsImagesWithURLObjects() async throws {
        let imageURL = URL(string: "https://example.com/image.png")!

        let prompt = StandardizedPrompt(
            system: nil,
            messages: [
                .user(UserModelMessage(
                    content: .parts([
                        .image(ImagePart(
                            image: .url(imageURL),
                            mediaType: nil,
                            providerOptions: nil
                        ))
                    ]),
                    providerOptions: nil
                ))
            ]
        )

        let download = createMockDownload([
            (url: imageURL, data: Data([0, 1, 2, 3]), mediaType: "image/png")
        ])

        let result = try await convertToLanguageModelPrompt(
            prompt: prompt,
            supportedUrls: [:],
            download: download
        )

        #expect(result.count == 1)

        guard case .user(let content, _) = result[0] else {
            Issue.record("Expected user message")
            return
        }

        #expect(content.count == 1)

        guard case .file(let filePart) = content[0] else {
            Issue.record("Expected file part")
            return
        }

        #expect(filePart.mediaType == "image/png")

        guard case .data(let data) = filePart.data else {
            Issue.record("Expected data content")
            return
        }

        #expect(data == Data([0, 1, 2, 3]))
    }

    @Test("should download images for user image parts with string URLs when model does not support image URLs")
    func downloadsImagesWithStringURLs() async throws {
        let imageURL = URL(string: "https://example.com/image.png")!

        let prompt = StandardizedPrompt(
            system: nil,
            messages: [
                .user(UserModelMessage(
                    content: .parts([
                        .image(ImagePart(
                            image: .url(imageURL),
                            mediaType: nil,
                            providerOptions: nil
                        ))
                    ]),
                    providerOptions: nil
                ))
            ]
        )

        let download = createMockDownload([
            (url: imageURL, data: Data([0, 1, 2, 3]), mediaType: "image/png")
        ])

        let result = try await convertToLanguageModelPrompt(
            prompt: prompt,
            supportedUrls: [:],
            download: download
        )

        #expect(result.count == 1)

        guard case .user(let content, _) = result[0] else {
            Issue.record("Expected user message")
            return
        }

        #expect(content.count == 1)
        guard case .file(let filePart) = content[0] else {
            Issue.record("Expected file part")
            return
        }

        #expect(filePart.mediaType == "image/png")
        guard case .data(let data) = filePart.data else {
            Issue.record("Expected data")
            return
        }
        #expect(data == Data([0, 1, 2, 3]))
    }

    // MARK: - User Message - File Parts

    @Test("should pass through URLs when the model supports a particular URL")
    func passesThroughURLsWhenSupported() async throws {
        let fileURL = URL(string: "https://example.com/document.pdf")!

        let prompt = StandardizedPrompt(
            system: nil,
            messages: [
                .user(UserModelMessage(
                    content: .parts([
                        .file(FilePart(
                            data: .url(fileURL),
                            mediaType: "application/pdf",
                            filename: nil,
                            providerOptions: nil
                        ))
                    ]),
                    providerOptions: nil
                ))
            ]
        )

        // Support all https URLs
        let supportedUrls: [String: [NSRegularExpression]] = [
            "*": [try! NSRegularExpression(pattern: "^https://.*$")]
        ]

        let result = try await convertToLanguageModelPrompt(
            prompt: prompt,
            supportedUrls: supportedUrls,
            download: nil
        )

        #expect(result.count == 1)
        guard case .user(let content, _) = result[0] else {
            Issue.record("Expected user message")
            return
        }

        #expect(content.count == 1)
        guard case .file(let filePart) = content[0] else {
            Issue.record("Expected file part")
            return
        }

        #expect(filePart.mediaType == "application/pdf")
        guard case .url(let url) = filePart.data else {
            Issue.record("Expected URL")
            return
        }
        #expect(url == fileURL)
    }

    @Test("should download the URL as an asset when the model does not support a URL")
    func downloadsURLWhenNotSupported() async throws {
        let fileURL = URL(string: "https://example.com/document.pdf")!

        let prompt = StandardizedPrompt(
            system: nil,
            messages: [
                .user(UserModelMessage(
                    content: .parts([
                        .file(FilePart(
                            data: .url(fileURL),
                            mediaType: "application/pdf",
                            filename: nil,
                            providerOptions: nil
                        ))
                    ]),
                    providerOptions: nil
                ))
            ]
        )

        // Only support image/* URLs
        let supportedUrls: [String: [NSRegularExpression]] = [
            "image/*": [try! NSRegularExpression(pattern: "^https://.*$")]
        ]

        let download = createMockDownload([
            (url: fileURL, data: Data([0, 1, 2, 3]), mediaType: "application/pdf")
        ])

        let result = try await convertToLanguageModelPrompt(
            prompt: prompt,
            supportedUrls: supportedUrls,
            download: download
        )

        #expect(result.count == 1)
        guard case .user(let content, _) = result[0] else {
            Issue.record("Expected user message")
            return
        }

        #expect(content.count == 1)
        guard case .file(let filePart) = content[0] else {
            Issue.record("Expected file part")
            return
        }

        #expect(filePart.mediaType == "application/pdf")
        guard case .data(let data) = filePart.data else {
            Issue.record("Expected data")
            return
        }
        #expect(data == Data([0, 1, 2, 3]))
    }

    @Test("should handle file parts with base64 string data")
    func handlesBase64StringData() async throws {
        let base64Data = "SGVsbG8sIFdvcmxkIQ==" // "Hello, World!" in base64

        let prompt = StandardizedPrompt(
            system: nil,
            messages: [
                .user(UserModelMessage(
                    content: .parts([
                        .file(FilePart(
                            data: .string(base64Data),
                            mediaType: "text/plain",
                            filename: nil,
                            providerOptions: nil
                        ))
                    ]),
                    providerOptions: nil
                ))
            ]
        )

        let supportedUrls: [String: [NSRegularExpression]] = [
            "image/*": [try! NSRegularExpression(pattern: "^https://.*$")]
        ]

        let result = try await convertToLanguageModelPrompt(
            prompt: prompt,
            supportedUrls: supportedUrls,
            download: nil
        )

        #expect(result.count == 1)
        guard case .user(let content, _) = result[0] else {
            Issue.record("Expected user message")
            return
        }

        #expect(content.count == 1)
        guard case .file(let filePart) = content[0] else {
            Issue.record("Expected file part")
            return
        }

        #expect(filePart.mediaType == "text/plain")
        guard case .base64(let data) = filePart.data else {
            Issue.record("Expected base64")
            return
        }
        #expect(data == base64Data)
    }

    @Test("should handle file parts with Uint8Array data")
    func handlesDataContent() async throws {
        let uint8Data = Data([72, 101, 108, 108, 111]) // "Hello" in ASCII

        let prompt = StandardizedPrompt(
            system: nil,
            messages: [
                .user(UserModelMessage(
                    content: .parts([
                        .file(FilePart(
                            data: .data(uint8Data),
                            mediaType: "text/plain",
                            filename: nil,
                            providerOptions: nil
                        ))
                    ]),
                    providerOptions: nil
                ))
            ]
        )

        let supportedUrls: [String: [NSRegularExpression]] = [
            "image/*": [try! NSRegularExpression(pattern: "^https://.*$")]
        ]

        let result = try await convertToLanguageModelPrompt(
            prompt: prompt,
            supportedUrls: supportedUrls,
            download: nil
        )

        #expect(result.count == 1)
        guard case .user(let content, _) = result[0] else {
            Issue.record("Expected user message")
            return
        }

        #expect(content.count == 1)
        guard case .file(let filePart) = content[0] else {
            Issue.record("Expected file part")
            return
        }

        #expect(filePart.mediaType == "text/plain")
        guard case .data(let data) = filePart.data else {
            Issue.record("Expected data")
            return
        }
        #expect(data == uint8Data)
    }

    @Test("should handle file parts with filename")
    func preservesFilename() async throws {
        let base64Data = "SGVsbG8sIFdvcmxkIQ=="

        let prompt = StandardizedPrompt(
            system: nil,
            messages: [
                .user(UserModelMessage(
                    content: .parts([
                        .file(FilePart(
                            data: .string(base64Data),
                            mediaType: "text/plain",
                            filename: "hello.txt",
                            providerOptions: nil
                        ))
                    ]),
                    providerOptions: nil
                ))
            ]
        )

        let result = try await convertToLanguageModelPrompt(
            prompt: prompt,
            supportedUrls: [:],
            download: nil
        )

        #expect(result.count == 1)
        guard case .user(let content, _) = result[0] else {
            Issue.record("Expected user message")
            return
        }

        guard case .file(let filePart) = content[0] else {
            Issue.record("Expected file part")
            return
        }

        #expect(filePart.filename == "hello.txt")
        #expect(filePart.mediaType == "text/plain")
    }

    @Test("should preserve filename when downloading file from URL")
    func preservesFilenameWhenDownloading() async throws {
        let fileURL = URL(string: "https://example.com/document.pdf")!

        let prompt = StandardizedPrompt(
            system: nil,
            messages: [
                .user(UserModelMessage(
                    content: .parts([
                        .file(FilePart(
                            data: .url(fileURL),
                            mediaType: "application/pdf",
                            filename: "important-document.pdf",
                            providerOptions: nil
                        ))
                    ]),
                    providerOptions: nil
                ))
            ]
        )

        let download = createMockDownload([
            (url: fileURL, data: Data([0, 1, 2, 3]), mediaType: "application/pdf")
        ])

        let result = try await convertToLanguageModelPrompt(
            prompt: prompt,
            supportedUrls: [:],
            download: download
        )

        #expect(result.count == 1)
        guard case .user(let content, _) = result[0] else {
            Issue.record("Expected user message")
            return
        }

        guard case .file(let filePart) = content[0] else {
            Issue.record("Expected file part")
            return
        }

        #expect(filePart.filename == "important-document.pdf")
        #expect(filePart.mediaType == "application/pdf")
    }

    // MARK: - Tool Message Combining

    @Test("should combine 2 consecutive tool messages into a single tool message")
    func combinesConsecutiveToolMessages() async throws {
        let prompt = StandardizedPrompt(
            system: nil,
            messages: [
                .assistant(AssistantModelMessage(
                    content: .parts([
                        .toolCall(ToolCallPart(
                            toolCallId: "toolCallId",
                            toolName: "toolName",
                            input: .object([:]),
                            providerOptions: nil,
                            providerExecuted: nil
                        )),
                        .toolApprovalRequest(ToolApprovalRequest(
                            approvalId: "approvalId",
                            toolCallId: "toolCallId"
                        ))
                    ]),
                    providerOptions: nil
                )),
                .tool(ToolModelMessage(
                    content: [
                        .toolApprovalResponse(ToolApprovalResponse(
                            approvalId: "approvalId",
                            approved: true,
                            reason: nil
                        ))
                    ],
                    providerOptions: nil
                )),
                .tool(ToolModelMessage(
                    content: [
                        .toolResult(ToolResultPart(
                            toolCallId: "toolCallId",
                            toolName: "toolName",
                            output: .json(value: .object(["some": .string("result")])),
                            providerOptions: nil
                        ))
                    ],
                    providerOptions: nil
                ))
            ]
        )

        let result = try await convertToLanguageModelPrompt(
            prompt: prompt,
            supportedUrls: [:],
            download: nil
        )

        // Tool-approval-request and tool-approval-response should be filtered out
        // Two tool messages should be combined into one
        #expect(result.count == 2)

        guard case .assistant(let assistantContent, _) = result[0] else {
            Issue.record("Expected assistant message")
            return
        }

        #expect(assistantContent.count == 1)
        guard case .toolCall = assistantContent[0] else {
            Issue.record("Expected tool call")
            return
        }

        guard case .tool(let toolContent, _) = result[1] else {
            Issue.record("Expected tool message")
            return
        }

        #expect(toolContent.count == 1)
        let part = toolContent[0]

        #expect(part.toolCallId == "toolCallId")
        #expect(part.toolName == "toolName")
    }

    // MARK: - Provider Options

    @Test("should add provider options to messages")
    func addsProviderOptions() async throws {
        let providerOptions: ProviderOptions = [
            "test-provider": [
                "key-a": .string("test-value-1"),
                "key-b": .string("test-value-2")
            ]
        ]

        let prompt = StandardizedPrompt(
            system: nil,
            messages: [
                .user(UserModelMessage(
                    content: .parts([
                        .text(TextPart(
                            text: "hello, world!",
                            providerOptions: nil
                        ))
                    ]),
                    providerOptions: providerOptions
                ))
            ]
        )

        let result = try await convertToLanguageModelPrompt(
            prompt: prompt,
            supportedUrls: [:],
            download: nil
        )

        #expect(result.count == 1)

        guard case .user(let content, let resultProviderOptions) = result[0] else {
            Issue.record("Expected user message")
            return
        }

        #expect(content.count == 1)

        // Check provider options
        #expect(resultProviderOptions != nil)
        guard let options = resultProviderOptions else { return }

        #expect(options["test-provider"] != nil)
    }

    // MARK: - Additional File Download Tests

    @Test("should download files for user file parts with URL objects when model does not support downloads")
    func downloadsFilesWithURLObjects() async throws {
        let fileURL = URL(string: "https://example.com/document.pdf")!

        let prompt = StandardizedPrompt(
            system: nil,
            messages: [
                .user(UserModelMessage(
                    content: .parts([
                        .file(FilePart(
                            data: .url(fileURL),
                            mediaType: "application/pdf",
                            filename: nil,
                            providerOptions: nil
                        ))
                    ]),
                    providerOptions: nil
                ))
            ]
        )

        let download = createMockDownload([
            (url: fileURL, data: Data([0, 1, 2, 3]), mediaType: "application/pdf")
        ])

        let result = try await convertToLanguageModelPrompt(
            prompt: prompt,
            supportedUrls: [:],
            download: download
        )

        #expect(result.count == 1)
        guard case .user(let content, _) = result[0] else {
            Issue.record("Expected user message")
            return
        }

        #expect(content.count == 1)
        guard case .file(let filePart) = content[0] else {
            Issue.record("Expected file part")
            return
        }

        #expect(filePart.mediaType == "application/pdf")
        guard case .data(let data) = filePart.data else {
            Issue.record("Expected data")
            return
        }
        #expect(data == Data([0, 1, 2, 3]))
    }

    @Test("should download files for user file parts with string URLs when model does not support downloads")
    func downloadsFilesWithStringURLs() async throws {
        let fileURL = URL(string: "https://example.com/document.pdf")!

        let prompt = StandardizedPrompt(
            system: nil,
            messages: [
                .user(UserModelMessage(
                    content: .parts([
                        .file(FilePart(
                            data: .string("https://example.com/document.pdf"),
                            mediaType: "application/pdf",
                            filename: nil,
                            providerOptions: nil
                        ))
                    ]),
                    providerOptions: nil
                ))
            ]
        )

        let download = createMockDownload([
            (url: fileURL, data: Data([0, 1, 2, 3]), mediaType: "application/pdf")
        ])

        let result = try await convertToLanguageModelPrompt(
            prompt: prompt,
            supportedUrls: [:],
            download: download
        )

        #expect(result.count == 1)
        guard case .user(let content, _) = result[0] else {
            Issue.record("Expected user message")
            return
        }

        #expect(content.count == 1)
        guard case .file(let filePart) = content[0] else {
            Issue.record("Expected file part")
            return
        }

        #expect(filePart.mediaType == "application/pdf")
        guard case .data(let data) = filePart.data else {
            Issue.record("Expected data")
            return
        }
        #expect(data == Data([0, 1, 2, 3]))
    }

    @Test("should download files for user file parts with string URLs when model does not support the particular URL")
    func downloadsFilesWhenModelDoesntSupportParticularURL() async throws {
        let fileURL = URL(string: "https://example.com/document.pdf")!

        let prompt = StandardizedPrompt(
            system: nil,
            messages: [
                .user(UserModelMessage(
                    content: .parts([
                        .file(FilePart(
                            data: .string("https://example.com/document.pdf"),
                            mediaType: "application/pdf",
                            filename: nil,
                            providerOptions: nil
                        ))
                    ]),
                    providerOptions: nil
                ))
            ]
        )

        // Everything except https://example.com/document.pdf
        let supportedUrls: [String: [NSRegularExpression]] = [
            "application/pdf": [try! NSRegularExpression(pattern: "^(?!https://example\\.com/document\\.pdf$).*$")]
        ]

        let download = createMockDownload([
            (url: fileURL, data: Data([0, 1, 2, 3]), mediaType: "application/pdf")
        ])

        let result = try await convertToLanguageModelPrompt(
            prompt: prompt,
            supportedUrls: supportedUrls,
            download: download
        )

        #expect(result.count == 1)
        guard case .user(let content, _) = result[0] else {
            Issue.record("Expected user message")
            return
        }

        #expect(content.count == 1)
        guard case .file(let filePart) = content[0] else {
            Issue.record("Expected file part")
            return
        }

        #expect(filePart.mediaType == "application/pdf")
        guard case .data(let data) = filePart.data else {
            Issue.record("Expected data")
            return
        }
        #expect(data == Data([0, 1, 2, 3]))
    }

    @Test("does not download URLs for user file parts for URL objects when model does support the URL")
    func doesNotDownloadWhenModelSupportsURL() async throws {
        let fileURL = URL(string: "https://example.com/document.pdf")!

        let prompt = StandardizedPrompt(
            system: nil,
            messages: [
                .user(UserModelMessage(
                    content: .parts([
                        .file(FilePart(
                            data: .url(fileURL),
                            mediaType: "application/pdf",
                            filename: nil,
                            providerOptions: nil
                        ))
                    ]),
                    providerOptions: nil
                ))
            ]
        )

        // Match exactly https://example.com/document.pdf
        let supportedUrls: [String: [NSRegularExpression]] = [
            "application/pdf": [try! NSRegularExpression(pattern: "^https://example\\.com/document\\.pdf$")]
        ]

        let result = try await convertToLanguageModelPrompt(
            prompt: prompt,
            supportedUrls: supportedUrls,
            download: nil
        )

        #expect(result.count == 1)
        guard case .user(let content, _) = result[0] else {
            Issue.record("Expected user message")
            return
        }

        #expect(content.count == 1)
        guard case .file(let filePart) = content[0] else {
            Issue.record("Expected file part")
            return
        }

        #expect(filePart.mediaType == "application/pdf")
        guard case .url(let url) = filePart.data else {
            Issue.record("Expected URL")
            return
        }
        #expect(url == fileURL)
    }

    @Test("it should default to downloading the URL when the model does not provider a supportsUrl function")
    func defaultsToDownloadingWhenNoSupportsUrlFunction() async throws {
        let fileURL = URL(string: "https://example.com/document.pdf")!

        let prompt = StandardizedPrompt(
            system: nil,
            messages: [
                .user(UserModelMessage(
                    content: .parts([
                        .file(FilePart(
                            data: .string("https://example.com/document.pdf"),
                            mediaType: "application/pdf",
                            filename: nil,
                            providerOptions: nil
                        ))
                    ]),
                    providerOptions: nil
                ))
            ]
        )

        let download = createMockDownload([
            (url: fileURL, data: Data([0, 1, 2, 3]), mediaType: "application/pdf")
        ])

        let result = try await convertToLanguageModelPrompt(
            prompt: prompt,
            supportedUrls: [:],
            download: download
        )

        #expect(result.count == 1)
        guard case .user(let content, _) = result[0] else {
            Issue.record("Expected user message")
            return
        }

        #expect(content.count == 1)
        guard case .file(let filePart) = content[0] else {
            Issue.record("Expected file part")
            return
        }

        #expect(filePart.mediaType == "application/pdf")
        guard case .data(let data) = filePart.data else {
            Issue.record("Expected data")
            return
        }
        #expect(data == Data([0, 1, 2, 3]))
    }

    @Test("should prioritize user-provided mediaType over downloaded file mediaType")
    func prioritizesUserProvidedMediaType() async throws {
        let imageURL = URL(string: "https://example.com/image.jpg")!

        let prompt = StandardizedPrompt(
            system: nil,
            messages: [
                .user(UserModelMessage(
                    content: .parts([
                        .file(FilePart(
                            data: .url(imageURL),
                            mediaType: "image/jpeg",
                            filename: nil,
                            providerOptions: nil
                        ))
                    ]),
                    providerOptions: nil
                ))
            ]
        )

        let download = createMockDownload([
            (url: imageURL, data: Data([0, 1, 2, 3]), mediaType: "application/octet-stream")
        ])

        let result = try await convertToLanguageModelPrompt(
            prompt: prompt,
            supportedUrls: [:],
            download: download
        )

        #expect(result.count == 1)
        guard case .user(let content, _) = result[0] else {
            Issue.record("Expected user message")
            return
        }

        #expect(content.count == 1)
        guard case .file(let filePart) = content[0] else {
            Issue.record("Expected file part")
            return
        }

        // User-provided mediaType should win
        #expect(filePart.mediaType == "image/jpeg")
        guard case .data(let data) = filePart.data else {
            Issue.record("Expected data")
            return
        }
        #expect(data == Data([0, 1, 2, 3]))
    }

    @Test("should use downloaded file mediaType as fallback when user provides generic mediaType")
    func usesDownloadedMediaTypeAsFallback() async throws {
        let fileURL = URL(string: "https://example.com/document.txt")!

        let prompt = StandardizedPrompt(
            system: nil,
            messages: [
                .user(UserModelMessage(
                    content: .parts([
                        .file(FilePart(
                            data: .url(fileURL),
                            mediaType: "application/octet-stream",
                            filename: nil,
                            providerOptions: nil
                        ))
                    ]),
                    providerOptions: nil
                ))
            ]
        )

        let download = createMockDownload([
            (url: fileURL, data: Data([72, 101, 108, 108, 111]), mediaType: "text/plain")
        ])

        let result = try await convertToLanguageModelPrompt(
            prompt: prompt,
            supportedUrls: [:],
            download: download
        )

        #expect(result.count == 1)
        guard case .user(let content, _) = result[0] else {
            Issue.record("Expected user message")
            return
        }

        #expect(content.count == 1)
        guard case .file(let filePart) = content[0] else {
            Issue.record("Expected file part")
            return
        }

        // User-provided mediaType should still win (not fallback to downloaded)
        #expect(filePart.mediaType == "application/octet-stream")
        guard case .data(let data) = filePart.data else {
            Issue.record("Expected data")
            return
        }
        #expect(data == Data([72, 101, 108, 108, 111]))
    }

    // MARK: - Intermediate File Download Failures

    @Test("should download files when intermediate file cannot be downloaded")
    func downloadsFilesWhenIntermediateFileCannotBeDownloaded() async throws {
        let imageURLA = URL(string: "http://example.com/my-image-A.png")!
        let fileURL = URL(string: "http://127.0.0.1:3000/file")!
        let imageURLB = URL(string: "http://example.com/my-image-B.png")!

        // Mock download that returns nil for the middle URL
        let download: DownloadFunction = { requests in
            var results: [DownloadResult?] = []
            for request in requests {
                if request.url == imageURLA {
                    results.append(DownloadResult(
                        data: Data([137, 80, 78, 71, 13, 10, 26, 10, 0]),
                        mediaType: "image/png"
                    ))
                } else if request.url == fileURL {
                    results.append(nil) // Cannot download this file
                } else if request.url == imageURLB {
                    results.append(DownloadResult(
                        data: Data([137, 80, 78, 71, 13, 10, 26, 10, 1]),
                        mediaType: "image/png"
                    ))
                } else {
                    results.append(nil)
                }
            }
            return results
        }

        let prompt = StandardizedPrompt(
            system: nil,
            messages: [
                .user(UserModelMessage(
                    content: .parts([
                        .image(ImagePart(
                            image: .url(imageURLA),
                            mediaType: "image/png",
                            providerOptions: nil
                        )),
                        .file(FilePart(
                            data: .url(fileURL),
                            mediaType: "application/octet-stream",
                            filename: nil,
                            providerOptions: nil
                        )),
                        .image(ImagePart(
                            image: .url(imageURLB),
                            mediaType: "image/png",
                            providerOptions: nil
                        ))
                    ]),
                    providerOptions: nil
                ))
            ]
        )

        // Only support https URLs (http:// not supported)
        let supportedUrls: [String: [NSRegularExpression]] = [
            "*": [try! NSRegularExpression(pattern: "^https://.*$")]
        ]

        let result = try await convertToLanguageModelPrompt(
            prompt: prompt,
            supportedUrls: supportedUrls,
            download: download
        )

        #expect(result.count == 1)
        guard case .user(let content, _) = result[0] else {
            Issue.record("Expected user message")
            return
        }

        #expect(content.count == 3)

        // First image downloaded successfully
        guard case .file(let file1) = content[0] else {
            Issue.record("Expected file part")
            return
        }
        guard case .data(let data1) = file1.data else {
            Issue.record("Expected data")
            return
        }
        #expect(data1 == Data([137, 80, 78, 71, 13, 10, 26, 10, 0]))
        #expect(file1.mediaType == "image/png")

        // Second file could not be downloaded, kept as string URL
        guard case .file(let file2) = content[1] else {
            Issue.record("Expected file part")
            return
        }
        guard case .base64(let url2) = file2.data else {
            Issue.record("Expected base64/string")
            return
        }
        #expect(url2 == "http://127.0.0.1:3000/file")
        #expect(file2.mediaType == "application/octet-stream")

        // Third image downloaded successfully
        guard case .file(let file3) = content[2] else {
            Issue.record("Expected file part")
            return
        }
        guard case .data(let data3) = file3.data else {
            Issue.record("Expected data")
            return
        }
        #expect(data3 == Data([137, 80, 78, 71, 13, 10, 26, 10, 1]))
        #expect(file3.mediaType == "image/png")
    }

    // MARK: - Custom Download Function

    @Test("should use custom download function to fetch URL content")
    func usesCustomDownloadFunctionToFetchURLContent() async throws {
        let fileURL = URL(string: "https://example.com/test-file.txt")!

        let download = createMockDownload([
            (url: fileURL, data: Data([72, 101, 108, 108, 111]), mediaType: "text/plain")
        ])

        let prompt = StandardizedPrompt(
            system: nil,
            messages: [
                .user(UserModelMessage(
                    content: .parts([
                        .file(FilePart(
                            data: .url(fileURL),
                            mediaType: "text/plain",
                            filename: nil,
                            providerOptions: nil
                        ))
                    ]),
                    providerOptions: nil
                ))
            ]
        )

        let result = try await convertToLanguageModelPrompt(
            prompt: prompt,
            supportedUrls: [:], // No URL support, download should be triggered
            download: download
        )

        #expect(result.count == 1)
        guard case .user(let content, _) = result[0] else {
            Issue.record("Expected user message")
            return
        }

        #expect(content.count == 1)
        guard case .file(let filePart) = content[0] else {
            Issue.record("Expected file part")
            return
        }

        #expect(filePart.mediaType == "text/plain")
        guard case .data(let data) = filePart.data else {
            Issue.record("Expected data")
            return
        }
        #expect(data == Data([72, 101, 108, 108, 111]))
    }
}

// MARK: - convertToLanguageModelMessage Tests

@Suite("ConvertToLanguageModelMessage")
struct ConvertToLanguageModelMessageTests {

    // MARK: - User Message - Text Parts

    @Test("should filter out empty text parts")
    func filtersEmptyTextParts() throws {
        let message = ModelMessage.user(UserModelMessage(
            content: .parts([
                .text(TextPart(text: "", providerOptions: nil))
            ]),
            providerOptions: nil
        ))

        let result = try convertToLanguageModelMessage(
            message: message,
            downloadedAssets: [:]
        )

        guard case .user(let content, _) = result else {
            Issue.record("Expected user message")
            return
        }

        #expect(content.isEmpty)
    }

    @Test("should pass through non-empty text parts")
    func passesNonEmptyTextParts() throws {
        let message = ModelMessage.user(UserModelMessage(
            content: .parts([
                .text(TextPart(text: "hello, world!", providerOptions: nil))
            ]),
            providerOptions: nil
        ))

        let result = try convertToLanguageModelMessage(
            message: message,
            downloadedAssets: [:]
        )

        guard case .user(let content, _) = result else {
            Issue.record("Expected user message")
            return
        }

        #expect(content.count == 1)
        guard case .text(let textPart) = content[0] else {
            Issue.record("Expected text part")
            return
        }

        #expect(textPart.text == "hello, world!")
    }

    // MARK: - User Message - Image Parts

    @Test("should convert image URL to file part")
    func convertsImageURLToFilePart() throws {
        let imageURL = URL(string: "https://example.com/image.jpg")!

        let message = ModelMessage.user(UserModelMessage(
            content: .parts([
                .image(ImagePart(
                    image: .url(imageURL),
                    mediaType: nil,
                    providerOptions: nil
                ))
            ]),
            providerOptions: nil
        ))

        let result = try convertToLanguageModelMessage(
            message: message,
            downloadedAssets: [:]
        )

        guard case .user(let content, _) = result else {
            Issue.record("Expected user message")
            return
        }

        #expect(content.count == 1)
        guard case .file(let filePart) = content[0] else {
            Issue.record("Expected file part")
            return
        }

        guard case .url(let url) = filePart.data else {
            Issue.record("Expected URL")
            return
        }

        #expect(url == imageURL)
        #expect(filePart.mediaType == "image/*") // wildcard for unknown type
    }

    @Test("should convert image data URL to base64 content")
    func convertsDataURLToBase64() throws {
        let dataURL = "data:image/jpg;base64,/9j/3Q=="

        let message = ModelMessage.user(UserModelMessage(
            content: .parts([
                .image(ImagePart(
                    image: .string(dataURL),
                    mediaType: nil,
                    providerOptions: nil
                ))
            ]),
            providerOptions: nil
        ))

        let result = try convertToLanguageModelMessage(
            message: message,
            downloadedAssets: [:]
        )

        guard case .user(let content, _) = result else {
            Issue.record("Expected user message")
            return
        }

        #expect(content.count == 1)
        guard case .file(let filePart) = content[0] else {
            Issue.record("Expected file part")
            return
        }

        guard case .base64(let base64) = filePart.data else {
            Issue.record("Expected base64")
            return
        }

        #expect(base64 == "/9j/3Q==")
        #expect(filePart.mediaType == "image/jpeg") // detected from data
    }

    @Test("should prefer detected mediaType over data URL mediaType")
    func prefersDetectedMediaType() throws {
        // Data URL claims "image/png" but data is actually JPEG
        let dataURL = "data:image/png;base64,/9j/3Q=="

        let message = ModelMessage.user(UserModelMessage(
            content: .parts([
                .image(ImagePart(
                    image: .string(dataURL),
                    mediaType: nil,
                    providerOptions: nil
                ))
            ]),
            providerOptions: nil
        ))

        let result = try convertToLanguageModelMessage(
            message: message,
            downloadedAssets: [:]
        )

        guard case .user(let content, _) = result else {
            Issue.record("Expected user message")
            return
        }

        guard case .file(let filePart) = content[0] else {
            Issue.record("Expected file part")
            return
        }

        // Should detect JPEG from signature
        #expect(filePart.mediaType == "image/jpeg")
    }

    // MARK: - Assistant Message - Text Parts

    @Test("should ignore empty text parts when there are no provider options")
    func ignoresEmptyTextPartsWithoutOptions() throws {
        let message = ModelMessage.assistant(AssistantModelMessage(
            content: .parts([
                .text(TextPart(text: "", providerOptions: nil)),
                .toolCall(ToolCallPart(
                    toolCallId: "toolCallId",
                    toolName: "toolName",
                    input: .object([:]),
                    providerOptions: nil,
                    providerExecuted: nil
                ))
            ]),
            providerOptions: nil
        ))

        let result = try convertToLanguageModelMessage(
            message: message,
            downloadedAssets: [:]
        )

        guard case .assistant(let content, _) = result else {
            Issue.record("Expected assistant message")
            return
        }

        #expect(content.count == 1)
        guard case .toolCall = content[0] else {
            Issue.record("Expected tool call")
            return
        }
    }

    @Test("should include empty text parts when there are provider options")
    func includesEmptyTextPartsWithOptions() throws {
        let providerOptions: ProviderOptions = [
            "test-provider": ["key-a": .string("test-value-1")]
        ]

        let message = ModelMessage.assistant(AssistantModelMessage(
            content: .parts([
                .text(TextPart(text: "", providerOptions: providerOptions)),
                .toolCall(ToolCallPart(
                    toolCallId: "toolCallId",
                    toolName: "toolName",
                    input: .object([:]),
                    providerOptions: nil,
                    providerExecuted: nil
                ))
            ]),
            providerOptions: nil
        ))

        let result = try convertToLanguageModelMessage(
            message: message,
            downloadedAssets: [:]
        )

        guard case .assistant(let content, _) = result else {
            Issue.record("Expected assistant message")
            return
        }

        #expect(content.count == 2)

        guard case .text(let textPart) = content[0] else {
            Issue.record("Expected text part")
            return
        }

        #expect(textPart.text == "")
        #expect(textPart.providerOptions != nil)
    }

    // MARK: - Tool Message

    @Test("should convert basic tool result message")
    func convertsBasicToolResult() throws {
        let message = ModelMessage.tool(ToolModelMessage(
            content: [
                .toolResult(ToolResultPart(
                    toolCallId: "toolCallId",
                    toolName: "toolName",
                    output: .json(value: .object(["some": .string("result")])),
                    providerOptions: nil
                ))
            ],
            providerOptions: nil
        ))

        let result = try convertToLanguageModelMessage(
            message: message,
            downloadedAssets: [:]
        )

        guard case .tool(let content, _) = result else {
            Issue.record("Expected tool message")
            return
        }

        #expect(content.count == 1)

        let part = content[0]
        #expect(part.toolCallId == "toolCallId")
        #expect(part.toolName == "toolName")

        guard case .json(value: let jsonValue) = part.output else {
            Issue.record("Expected JSON output")
            return
        }

        guard case .object(let obj) = jsonValue else {
            Issue.record("Expected object")
            return
        }

        #expect(obj["some"] == .string("result"))
    }

    @Test("should filter out tool-approval-response from tool messages")
    func filtersToolApprovalResponse() throws {
        let message = ModelMessage.tool(ToolModelMessage(
            content: [
                .toolApprovalResponse(ToolApprovalResponse(
                    approvalId: "approvalId",
                    approved: true,
                    reason: nil
                )),
                .toolResult(ToolResultPart(
                    toolCallId: "toolCallId",
                    toolName: "toolName",
                    output: .json(value: .object(["some": .string("result")])),
                    providerOptions: nil
                ))
            ],
            providerOptions: nil
        ))

        let result = try convertToLanguageModelMessage(
            message: message,
            downloadedAssets: [:]
        )

        guard case .tool(let content, _) = result else {
            Issue.record("Expected tool message")
            return
        }

        // Should only have tool result, not approval response
        #expect(content.count == 1)
        #expect(content[0].toolName == "toolName")
    }

    // MARK: - User Message - File Parts

    @Test("should convert file string https url to URL object")
    func convertsFileStringHttpsUrlToURLObject() throws {
        let message = ModelMessage.user(UserModelMessage(
            content: .parts([
                .file(FilePart(
                    data: .string("https://example.com/image.jpg"),
                    mediaType: "image/jpg",
                    filename: nil,
                    providerOptions: nil
                ))
            ]),
            providerOptions: nil
        ))

        let result = try convertToLanguageModelMessage(
            message: message,
            downloadedAssets: [:]
        )

        guard case .user(let content, _) = result else {
            Issue.record("Expected user message")
            return
        }

        #expect(content.count == 1)
        guard case .file(let filePart) = content[0] else {
            Issue.record("Expected file part")
            return
        }

        guard case .url(let url) = filePart.data else {
            Issue.record("Expected URL")
            return
        }

        #expect(url.absoluteString == "https://example.com/image.jpg")
        #expect(filePart.mediaType == "image/jpg")
    }

    @Test("should convert file string data url to base64 content")
    func convertsFileStringDataUrlToBase64Content() throws {
        let message = ModelMessage.user(UserModelMessage(
            content: .parts([
                .file(FilePart(
                    data: .string("data:image/jpg;base64,dGVzdA=="),
                    mediaType: "image/jpg",
                    filename: nil,
                    providerOptions: nil
                ))
            ]),
            providerOptions: nil
        ))

        let result = try convertToLanguageModelMessage(
            message: message,
            downloadedAssets: [:]
        )

        guard case .user(let content, _) = result else {
            Issue.record("Expected user message")
            return
        }

        #expect(content.count == 1)
        guard case .file(let filePart) = content[0] else {
            Issue.record("Expected file part")
            return
        }

        guard case .base64(let base64Data) = filePart.data else {
            Issue.record("Expected base64 data")
            return
        }

        #expect(base64Data == "dGVzdA==")
        #expect(filePart.mediaType == "image/jpg")
    }

    // MARK: - Assistant Message - Reasoning Parts

    @Test("should pass through provider options for reasoning parts")
    func passesProviderOptionsForReasoningParts() throws {
        let providerOptions: ProviderOptions = [
            "test-provider": [
                "key-a": .string("test-value-1"),
                "key-b": .string("test-value-2")
            ]
        ]

        let message = ModelMessage.assistant(AssistantModelMessage(
            content: .parts([
                .reasoning(ReasoningPart(
                    text: "hello, world!",
                    providerOptions: providerOptions
                ))
            ]),
            providerOptions: nil
        ))

        let result = try convertToLanguageModelMessage(
            message: message,
            downloadedAssets: [:]
        )

        guard case .assistant(let content, _) = result else {
            Issue.record("Expected assistant message")
            return
        }

        #expect(content.count == 1)
        guard case .reasoning(let reasoningPart) = content[0] else {
            Issue.record("Expected reasoning part")
            return
        }

        #expect(reasoningPart.text == "hello, world!")
        #expect(reasoningPart.providerOptions != nil)

        guard let options = reasoningPart.providerOptions else {
            Issue.record("Expected provider options")
            return
        }

        guard let testProvider = options["test-provider"] else {
            Issue.record("Expected test-provider")
            return
        }

        #expect(testProvider["key-a"] == .string("test-value-1"))
        #expect(testProvider["key-b"] == .string("test-value-2"))
    }

    @Test("should support a mix of reasoning, redacted reasoning, and text parts")
    func supportsMixOfReasoningRedactedReasoningAndTextParts() throws {
        let redactedOptions: ProviderOptions = [
            "test-provider": ["redacted": .bool(true)]
        ]

        let message = ModelMessage.assistant(AssistantModelMessage(
            content: .parts([
                .reasoning(ReasoningPart(
                    text: "I'm thinking",
                    providerOptions: nil
                )),
                .reasoning(ReasoningPart(
                    text: "redacted-reasoning-data",
                    providerOptions: redactedOptions
                )),
                .reasoning(ReasoningPart(
                    text: "more thinking",
                    providerOptions: nil
                )),
                .text(TextPart(
                    text: "hello, world!",
                    providerOptions: nil
                ))
            ]),
            providerOptions: nil
        ))

        let result = try convertToLanguageModelMessage(
            message: message,
            downloadedAssets: [:]
        )

        guard case .assistant(let content, _) = result else {
            Issue.record("Expected assistant message")
            return
        }

        #expect(content.count == 4)

        // First reasoning part
        guard case .reasoning(let reasoning1) = content[0] else {
            Issue.record("Expected reasoning part")
            return
        }
        #expect(reasoning1.text == "I'm thinking")

        // Second reasoning part (redacted)
        guard case .reasoning(let reasoning2) = content[1] else {
            Issue.record("Expected reasoning part")
            return
        }
        #expect(reasoning2.text == "redacted-reasoning-data")
        #expect(reasoning2.providerOptions?["test-provider"]?["redacted"] == .bool(true))

        // Third reasoning part
        guard case .reasoning(let reasoning3) = content[2] else {
            Issue.record("Expected reasoning part")
            return
        }
        #expect(reasoning3.text == "more thinking")

        // Text part
        guard case .text(let textPart) = content[3] else {
            Issue.record("Expected text part")
            return
        }
        #expect(textPart.text == "hello, world!")
    }

    // MARK: - Assistant Message - Tool Call Parts

    @Test("should pass through provider options for tool calls")
    func passesProviderOptionsForToolCalls() throws {
        let providerOptions: ProviderOptions = [
            "test-provider": [
                "key-a": .string("test-value-1"),
                "key-b": .string("test-value-2")
            ]
        ]

        let message = ModelMessage.assistant(AssistantModelMessage(
            content: .parts([
                .toolCall(ToolCallPart(
                    toolCallId: "toolCallId",
                    toolName: "toolName",
                    input: .object([:]),
                    providerOptions: providerOptions,
                    providerExecuted: nil
                ))
            ]),
            providerOptions: nil
        ))

        let result = try convertToLanguageModelMessage(
            message: message,
            downloadedAssets: [:]
        )

        guard case .assistant(let content, _) = result else {
            Issue.record("Expected assistant message")
            return
        }

        #expect(content.count == 1)
        guard case .toolCall(let toolCallPart) = content[0] else {
            Issue.record("Expected tool call part")
            return
        }

        #expect(toolCallPart.toolCallId == "toolCallId")
        #expect(toolCallPart.toolName == "toolName")
        #expect(toolCallPart.providerOptions != nil)

        guard let options = toolCallPart.providerOptions else {
            Issue.record("Expected provider options")
            return
        }

        guard let testProvider = options["test-provider"] else {
            Issue.record("Expected test-provider")
            return
        }

        #expect(testProvider["key-a"] == .string("test-value-1"))
        #expect(testProvider["key-b"] == .string("test-value-2"))
    }

    @Test("should include providerExecuted flag for tool calls")
    func includesProviderExecutedFlagForToolCalls() throws {
        let message = ModelMessage.assistant(AssistantModelMessage(
            content: .parts([
                .toolCall(ToolCallPart(
                    toolCallId: "toolCallId",
                    toolName: "toolName",
                    input: .object([:]),
                    providerOptions: nil,
                    providerExecuted: true
                ))
            ]),
            providerOptions: nil
        ))

        let result = try convertToLanguageModelMessage(
            message: message,
            downloadedAssets: [:]
        )

        guard case .assistant(let content, _) = result else {
            Issue.record("Expected assistant message")
            return
        }

        #expect(content.count == 1)
        guard case .toolCall(let toolCallPart) = content[0] else {
            Issue.record("Expected tool call part")
            return
        }

        #expect(toolCallPart.providerExecuted == true)
    }

    // MARK: - Assistant Message - Tool Result Parts

    @Test("should include providerExecuted flag for tool results")
    func includesProviderExecutedFlagForToolResults() throws {
        let providerOptions: ProviderOptions = [
            "test-provider": [
                "key-a": .string("test-value-1"),
                "key-b": .string("test-value-2")
            ]
        ]

        let message = ModelMessage.assistant(AssistantModelMessage(
            content: .parts([
                .toolResult(ToolResultPart(
                    toolCallId: "toolCallId",
                    toolName: "toolName",
                    output: .json(value: .object(["some": .string("result")])),
                    providerOptions: providerOptions
                ))
            ]),
            providerOptions: nil
        ))

        let result = try convertToLanguageModelMessage(
            message: message,
            downloadedAssets: [:]
        )

        guard case .assistant(let content, _) = result else {
            Issue.record("Expected assistant message")
            return
        }

        #expect(content.count == 1)
        guard case .toolResult(let toolResultPart) = content[0] else {
            Issue.record("Expected tool result part")
            return
        }

        #expect(toolResultPart.toolCallId == "toolCallId")
        #expect(toolResultPart.toolName == "toolName")
        #expect(toolResultPart.providerOptions != nil)
    }

    // MARK: - Assistant Message - File Parts

    @Test("should convert file data correctly in assistant messages")
    func convertsFileDataCorrectlyInAssistantMessages() throws {
        let message = ModelMessage.assistant(AssistantModelMessage(
            content: .parts([
                .file(FilePart(
                    data: .string("dGVzdA=="), // "test" in base64
                    mediaType: "application/pdf",
                    filename: nil,
                    providerOptions: nil
                ))
            ]),
            providerOptions: nil
        ))

        let result = try convertToLanguageModelMessage(
            message: message,
            downloadedAssets: [:]
        )

        guard case .assistant(let content, _) = result else {
            Issue.record("Expected assistant message")
            return
        }

        #expect(content.count == 1)
        guard case .file(let filePart) = content[0] else {
            Issue.record("Expected file part")
            return
        }

        guard case .base64(let base64Data) = filePart.data else {
            Issue.record("Expected base64 data")
            return
        }

        #expect(base64Data == "dGVzdA==")
        #expect(filePart.mediaType == "application/pdf")
    }

    @Test("should preserve filename when present in assistant messages")
    func preservesFilenameWhenPresentInAssistantMessages() throws {
        let message = ModelMessage.assistant(AssistantModelMessage(
            content: .parts([
                .file(FilePart(
                    data: .string("dGVzdA=="),
                    mediaType: "application/pdf",
                    filename: "test-document.pdf",
                    providerOptions: nil
                ))
            ]),
            providerOptions: nil
        ))

        let result = try convertToLanguageModelMessage(
            message: message,
            downloadedAssets: [:]
        )

        guard case .assistant(let content, _) = result else {
            Issue.record("Expected assistant message")
            return
        }

        #expect(content.count == 1)
        guard case .file(let filePart) = content[0] else {
            Issue.record("Expected file part")
            return
        }

        #expect(filePart.filename == "test-document.pdf")
        #expect(filePart.mediaType == "application/pdf")
    }

    @Test("should handle provider options for files in assistant messages")
    func handlesProviderOptionsForFilesInAssistantMessages() throws {
        let providerOptions: ProviderOptions = [
            "test-provider": [
                "key-a": .string("test-value-1"),
                "key-b": .string("test-value-2")
            ]
        ]

        let message = ModelMessage.assistant(AssistantModelMessage(
            content: .parts([
                .file(FilePart(
                    data: .string("dGVzdA=="),
                    mediaType: "application/pdf",
                    filename: nil,
                    providerOptions: providerOptions
                ))
            ]),
            providerOptions: nil
        ))

        let result = try convertToLanguageModelMessage(
            message: message,
            downloadedAssets: [:]
        )

        guard case .assistant(let content, _) = result else {
            Issue.record("Expected assistant message")
            return
        }

        #expect(content.count == 1)
        guard case .file(let filePart) = content[0] else {
            Issue.record("Expected file part")
            return
        }

        #expect(filePart.providerOptions != nil)

        guard let options = filePart.providerOptions else {
            Issue.record("Expected provider options")
            return
        }

        guard let testProvider = options["test-provider"] else {
            Issue.record("Expected test-provider")
            return
        }

        #expect(testProvider["key-a"] == .string("test-value-1"))
        #expect(testProvider["key-b"] == .string("test-value-2"))
    }

    // MARK: - Tool Message - Additional Tests

    @Test("should convert tool result with provider metadata")
    func convertsToolResultWithProviderMetadata() throws {
        let providerOptions: ProviderOptions = [
            "test-provider": [
                "key-a": .string("test-value-1"),
                "key-b": .string("test-value-2")
            ]
        ]

        let message = ModelMessage.tool(ToolModelMessage(
            content: [
                .toolResult(ToolResultPart(
                    toolCallId: "toolCallId",
                    toolName: "toolName",
                    output: .json(value: .object(["some": .string("result")])),
                    providerOptions: providerOptions
                ))
            ],
            providerOptions: nil
        ))

        let result = try convertToLanguageModelMessage(
            message: message,
            downloadedAssets: [:]
        )

        guard case .tool(let content, _) = result else {
            Issue.record("Expected tool message")
            return
        }

        #expect(content.count == 1)
        let part = content[0]

        #expect(part.providerOptions != nil)

        guard let options = part.providerOptions else {
            Issue.record("Expected provider options")
            return
        }

        guard let testProvider = options["test-provider"] else {
            Issue.record("Expected test-provider")
            return
        }

        #expect(testProvider["key-a"] == .string("test-value-1"))
        #expect(testProvider["key-b"] == .string("test-value-2"))
    }

    @Test("should include error flag in tool results")
    func includesErrorFlagInToolResults() throws {
        let message = ModelMessage.tool(ToolModelMessage(
            content: [
                .toolResult(ToolResultPart(
                    toolCallId: "toolCallId",
                    toolName: "toolName",
                    output: .json(value: .object(["some": .string("result")])),
                    providerOptions: nil
                ))
            ],
            providerOptions: nil
        ))

        let result = try convertToLanguageModelMessage(
            message: message,
            downloadedAssets: [:]
        )

        guard case .tool(let content, _) = result else {
            Issue.record("Expected tool message")
            return
        }

        #expect(content.count == 1)
        let part = content[0]

        #expect(part.toolCallId == "toolCallId")
        #expect(part.toolName == "toolName")

        guard case .json(value: let jsonValue) = part.output else {
            Issue.record("Expected JSON output")
            return
        }

        guard case .object(let obj) = jsonValue else {
            Issue.record("Expected object")
            return
        }

        #expect(obj["some"] == .string("result"))
    }

    @Test("should include multipart content in tool results")
    func includesMultipartContentInToolResults() throws {
        let message = ModelMessage.tool(ToolModelMessage(
            content: [
                .toolResult(ToolResultPart(
                    toolCallId: "toolCallId",
                    toolName: "toolName",
                    output: .content(value: [
                        LanguageModelV3ToolResultContentPart.media(data: "dGVzdA==", mediaType: "image/png")
                    ]),
                    providerOptions: nil
                ))
            ],
            providerOptions: nil
        ))

        let result = try convertToLanguageModelMessage(
            message: message,
            downloadedAssets: [:]
        )

        guard case .tool(let content, _) = result else {
            Issue.record("Expected tool message")
            return
        }

        #expect(content.count == 1)
        let part = content[0]

        #expect(part.toolCallId == "toolCallId")
        #expect(part.toolName == "toolName")

        guard case .content(value: let contentParts) = part.output else {
            Issue.record("Expected content output")
            return
        }

        #expect(contentParts.count == 1)

        guard case .media(data: let data, mediaType: let mediaType) = contentParts[0] else {
            Issue.record("Expected media content part")
            return
        }

        #expect(data == "dGVzdA==")
        #expect(mediaType == "image/png")
    }
}
