/**
 Tests for stringifyForTelemetry function.

 Port of `@ai-sdk/ai/src/telemetry/stringify-for-telemetry.test.ts`.

 Tests JSON serialization of LanguageModelV4Prompt with special handling
 for Data (Uint8Array) content in file parts.
 */

import Testing
import Foundation
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import SwiftAISDK

@Suite("StringifyForTelemetry Tests", .serialized)
struct StringifyForTelemetryTests {

    @Test("should stringify a prompt with text parts")
    func stringifyTextPrompt() throws {
        let prompt: LanguageModelV4Prompt = [
            .system(content: "You are a helpful assistant.", providerOptions: nil),
            .user(
                content: [
                    .text(LanguageModelV4TextPart(text: "Hello!"))
                ],
                providerOptions: nil
            )
        ]

        let result = try stringifyForTelemetry(prompt)
        // Note: Swift JSONEncoder with sortedKeys outputs in alphabetical order
        let expected = """
        [{"content":"You are a helpful assistant.","role":"system"},{"content":[{"text":"Hello!","type":"text"}],"role":"user"}]
        """

        #expect(result == expected)
    }

    @Test("should convert Data images to base64 strings")
    func convertDataToBase64() throws {
        let imageData = Data([0x89, 0x50, 0x4e, 0x47, 0xff, 0xff])

        let prompt: LanguageModelV4Prompt = [
            .user(
                content: [
                    .file(
                        LanguageModelV4FilePart(
                            data: .data(imageData),
                            mediaType: "image/png"
                        )
                    )
                ],
                providerOptions: nil
            )
        ]

        let result = try stringifyForTelemetry(prompt)
        // Note: Swift JSONEncoder with sortedKeys outputs in alphabetical order
        let expected = """
        [{"content":[{"data":"iVBOR///","mediaType":"image/png","type":"file"}],"role":"user"}]
        """

        #expect(result == expected)
    }

    @Test("should preserve the file name and provider options")
    func preserveFileMetadata() throws {
        let imageData = Data([0x89, 0x50, 0x4e, 0x47, 0xff, 0xff])

        let prompt: LanguageModelV4Prompt = [
            .user(
                content: [
                    .file(
                        LanguageModelV4FilePart(
                            data: .data(imageData),
                            mediaType: "image/png",
                            filename: "image.png",
                            providerOptions: [
                                "anthropic": ["key": .string("value")]
                            ]
                        )
                    )
                ],
                providerOptions: nil
            )
        ]

        let result = try stringifyForTelemetry(prompt)
        // Note: Swift JSONEncoder with sortedKeys outputs in alphabetical order
        let expected = """
        [{"content":[{"data":"iVBOR///","filename":"image.png","mediaType":"image/png","providerOptions":{"anthropic":{"key":"value"}},"type":"file"}],"role":"user"}]
        """

        #expect(result == expected)
    }

    @Test("should keep URL images as is")
    func keepURLImages() throws {
        let imageUrl = URL(string: "https://example.com/image.jpg")!

        let prompt: LanguageModelV4Prompt = [
            .user(
                content: [
                    .text(LanguageModelV4TextPart(text: "Check this image:")),
                    .file(
                        LanguageModelV4FilePart(
                            data: .url(imageUrl),
                            mediaType: "image/jpeg"
                        )
                    )
                ],
                providerOptions: nil
            )
        ]

        let result = try stringifyForTelemetry(prompt)
        // Note: Swift JSONEncoder with sortedKeys outputs in alphabetical order
        let expected = """
        [{"content":[{"text":"Check this image:","type":"text"},{"data":"https://example.com/image.jpg","mediaType":"image/jpeg","type":"file"}],"role":"user"}]
        """

        #expect(result == expected)
    }

    @Test("should handle a mixed prompt with various content types")
    func handleMixedContent() throws {
        let imageData = Data([0x89, 0x50, 0x4e, 0x47, 0xff, 0xff])
        let imageUrl = URL(string: "https://example.com/image.jpg")!

        let prompt: LanguageModelV4Prompt = [
            .system(content: "You are a helpful assistant.", providerOptions: nil),
            .user(
                content: [
                    .file(
                        LanguageModelV4FilePart(
                            data: .data(imageData),
                            mediaType: "image/png"
                        )
                    ),
                    .file(
                        LanguageModelV4FilePart(
                            data: .url(imageUrl),
                            mediaType: "image/jpeg"
                        )
                    )
                ],
                providerOptions: nil
            ),
            .assistant(
                content: [
                    .text(LanguageModelV4TextPart(text: "I see the images!"))
                ],
                providerOptions: nil
            )
        ]

        let result = try stringifyForTelemetry(prompt)
        // Note: Swift JSONEncoder with sortedKeys outputs in alphabetical order
        let expected = """
        [{"content":"You are a helpful assistant.","role":"system"},{"content":[{"data":"iVBOR///","mediaType":"image/png","type":"file"},{"data":"https://example.com/image.jpg","mediaType":"image/jpeg","type":"file"}],"role":"user"},{"content":[{"text":"I see the images!","type":"text"}],"role":"assistant"}]
        """

        #expect(result == expected)
    }
}
