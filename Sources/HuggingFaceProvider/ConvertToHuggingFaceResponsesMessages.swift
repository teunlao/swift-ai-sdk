import Foundation
import AISDKProvider

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/huggingface/src/responses/convert-to-huggingface-responses-messages.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

struct HuggingFaceConvertedMessages {
    let input: JSONValue
    let warnings: [SharedV3Warning]
}

func convertToHuggingFaceResponsesMessages(
    prompt: LanguageModelV3Prompt
) throws -> HuggingFaceConvertedMessages {
    var messages: [JSONValue] = []
    var warnings: [SharedV3Warning] = []

    for message in prompt {
        switch message {
        case .system(let content, _):
            messages.append(.object([
                "role": .string("system"),
                "content": .string(content)
            ]))

        case .user(let parts, _):
            let convertedParts = try parts.map { part -> JSONValue in
                switch part {
                case .text(let textPart):
                    return .object([
                        "type": .string("input_text"),
                        "text": .string(textPart.text)
                    ])

                case .file(let filePart):
                    guard filePart.mediaType.hasPrefix("image/") else {
                        throw UnsupportedFunctionalityError(functionality: "file part media type \(filePart.mediaType)")
                    }

                    let normalizedMediaType = filePart.mediaType == "image/*" ? "image/jpeg" : filePart.mediaType
                    let imageURL: String
                    switch filePart.data {
                    case .url(let url):
                        imageURL = url.absoluteString
                    case .base64(let base64):
                        imageURL = "data:\(normalizedMediaType);base64,\(base64)"
                    case .data(let data):
                        imageURL = "data:\(normalizedMediaType);base64,\(data.base64EncodedString())"
                    }

                    return .object([
                        "type": .string("input_image"),
                        "image_url": .string(imageURL)
                    ])
                }
            }

            messages.append(.object([
                "role": .string("user"),
                "content": .array(convertedParts)
            ]))

        case .assistant(let parts, _):
            for part in parts {
                switch part {
                case .text(let textPart):
                    messages.append(.object([
                        "role": .string("assistant"),
                        "content": .array([
                            .object([
                                "type": .string("output_text"),
                                "text": .string(textPart.text)
                            ])
                        ])
                    ]))

                case .reasoning(let reasoningPart):
                    messages.append(.object([
                        "role": .string("assistant"),
                        "content": .array([
                            .object([
                                "type": .string("output_text"),
                                "text": .string(reasoningPart.text)
                            ])
                        ])
                    ]))

                case .toolCall, .toolResult:
                    // Tool calls/results are handled by the Responses API directly
                    continue

                case .file:
                    continue
                }
            }

        case .tool:
            warnings.append(.unsupported(feature: "tool messages", details: nil))
        }
    }

    return HuggingFaceConvertedMessages(input: .array(messages), warnings: warnings)
}
