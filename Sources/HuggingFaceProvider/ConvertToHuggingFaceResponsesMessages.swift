import Foundation
import AISDKProvider
import AISDKProviderUtils

struct HuggingFaceConvertedMessages {
    let input: JSONValue
    let warnings: [SharedV4Warning]
}

func convertToHuggingFaceResponsesMessages(
    prompt: LanguageModelV4Prompt
) throws -> HuggingFaceConvertedMessages {
    var messages: [JSONValue] = []
    var warnings: [SharedV4Warning] = []

    for message in prompt {
        switch message {
        case .system(let content, _):
            messages.append(.object(["role": .string("system"), "content": .string(content)]))

        case .user(let parts, _):
            let content = try parts.map { part -> JSONValue in
                switch part {
                case .text(let text):
                    return .object(["type": .string("input_text"), "text": .string(text.text)])
                case .file(let file):
                    let imageURL: String
                    switch file.data {
                    case .reference:
                        throw UnsupportedFunctionalityError(functionality: "file parts with provider references")
                    case .text:
                        throw UnsupportedFunctionalityError(functionality: "text file parts")
                    case let .url(url, _):
                        guard getTopLevelMediaType(file.mediaType) == "image" else {
                            throw UnsupportedFunctionalityError(functionality: "file part media type \(file.mediaType)")
                        }
                        imageURL = url.absoluteString
                    case .base64(let data):
                        guard getTopLevelMediaType(file.mediaType) == "image" else {
                            throw UnsupportedFunctionalityError(functionality: "file part media type \(file.mediaType)")
                        }
                        imageURL = "data:\(try resolveFullMediaType(part: file));base64,\(data)"
                    case .data(let data):
                        guard getTopLevelMediaType(file.mediaType) == "image" else {
                            throw UnsupportedFunctionalityError(functionality: "file part media type \(file.mediaType)")
                        }
                        // Encode bytes as base64 instead of upstream's Uint8Array comma interpolation.
                        imageURL = "data:\(try resolveFullMediaType(part: file));base64,\(data.base64EncodedString())"
                    }
                    return .object(["type": .string("input_image"), "image_url": .string(imageURL)])
                }
            }
            messages.append(.object(["role": .string("user"), "content": .array(content)]))

        case .assistant(let parts, _):
            for part in parts {
                let text: String
                switch part {
                case .text(let value): text = value.text
                case .reasoning(let value): text = value.text
                case .toolCall, .toolResult, .file, .custom, .reasoningFile: continue
                }
                messages.append(.object([
                    "role": .string("assistant"),
                    "content": .array([.object(["type": .string("output_text"), "text": .string(text)])])
                ]))
            }

        case .tool:
            warnings.append(.unsupported(feature: "tool messages", details: nil))
        }
    }

    return HuggingFaceConvertedMessages(input: .array(messages), warnings: warnings)
}
