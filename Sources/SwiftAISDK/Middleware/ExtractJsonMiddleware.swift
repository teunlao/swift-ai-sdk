/**
 Extracts JSON from text content by stripping markdown code fences.

 Port of `@ai-sdk/ai/src/middleware/extract-json-middleware.ts`. Useful with
 structured output from models that wrap JSON responses in markdown code blocks.
 */

import Foundation
import AISDKProvider

/// Configuration for `extractJsonMiddleware`.
public struct ExtractJsonOptions: Sendable {
    /// Custom transform applied to the full text of each text part, replacing the
    /// default markdown fence stripping. A streamed text part is buffered whole
    /// and emitted transformed at its end.
    public let transform: (@Sendable (_ text: String) -> String)?

    public init(transform: (@Sendable (_ text: String) -> String)? = nil) {
        self.transform = transform
    }
}

/// Creates a middleware that strips markdown code fences around JSON text.
public func extractJsonMiddleware(
    options: ExtractJsonOptions = ExtractJsonOptions()
) -> LanguageModelV4Middleware {
    let transform = options.transform ?? stripMarkdownCodeFence
    let hasCustomTransform = options.transform != nil

    return LanguageModelV4Middleware(
        wrapGenerate: { doGenerate, _, _, _ in
            let result = try await doGenerate()

            let content: [LanguageModelV4Content] = result.content.map { part in
                guard case .text(let text) = part else { return part }
                return .text(LanguageModelV4Text(
                    text: transform(text.text),
                    citations: text.citations,
                    providerMetadata: text.providerMetadata
                ))
            }

            return LanguageModelV4GenerateResult(
                content: content,
                finishReason: result.finishReason,
                usage: result.usage,
                providerMetadata: result.providerMetadata,
                request: result.request,
                response: result.response,
                warnings: result.warnings
            )
        },
        wrapStream: { _, doStream, _, _ in
            let result = try await doStream()
            let extractor = JsonStreamExtractor(transform: transform, hasCustomTransform: hasCustomTransform)
            return LanguageModelV4StreamResult(
                stream: pipeMiddlewareStream(result.stream) { extractor.process($0) },
                request: result.request,
                response: result.response
            )
        }
    )
}

// MARK: - Text transforms

private let fencePrefixPattern = try! NSRegularExpression(pattern: #"\A```(?:json)?\s*\n?"#)
private let completeFencePrefixPattern = try! NSRegularExpression(pattern: #"\A```(?:json)?\s*\n"#)
private let fenceSuffixPattern = try! NSRegularExpression(pattern: #"\n?```\s*\z"#)

/// Default transform: strips a leading and a trailing markdown code fence, then trims.
@Sendable
private func stripMarkdownCodeFence(_ text: String) -> String {
    removingFirstMatch(of: fenceSuffixPattern, in: removingFirstMatch(of: fencePrefixPattern, in: text))
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func stripMarkdownCodeFenceSuffix(_ text: String) -> String {
    let stripped = removingFirstMatch(of: fenceSuffixPattern, in: text)
    guard let lastNonWhitespace = stripped.lastIndex(where: { !$0.isWhitespace }) else { return "" }
    return String(stripped[...lastNonWhitespace])
}

private func removingFirstMatch(of regex: NSRegularExpression, in text: String) -> String {
    let range = NSRange(text.startIndex..., in: text)
    guard let match = regex.firstMatch(in: text, range: range),
          let matchRange = Range(match.range, in: text)
    else {
        return text
    }
    return text.replacingCharacters(in: matchRange, with: "")
}

/// Index from which the text could still become trailing whitespace or a closing fence.
private func potentialSuffixStart(_ text: String) -> String.Index {
    var index = text.endIndex

    func previousIs(_ predicate: (Character) -> Bool) -> Bool {
        index > text.startIndex && predicate(text[text.index(before: index)])
    }

    while previousIs(\.isWhitespace) {
        index = text.index(before: index)
    }

    var backtickCount = 0
    while backtickCount < 3 && previousIs({ $0 == "`" }) {
        index = text.index(before: index)
        backtickCount += 1
    }

    if backtickCount > 0 {
        while previousIs(\.isWhitespace) {
            index = text.index(before: index)
        }
    }

    return index
}

// MARK: - Stream

/// The upstream `TransformStream` state of one stream. Its single pump task
/// (`pipeMiddlewareStream`) is the only caller of `process`.
private final class JsonStreamExtractor: @unchecked Sendable {
    private enum Phase {
        case prefix
        case streaming
        case buffering
    }

    private struct TextBlock {
        let startEvent: LanguageModelV4StreamPart
        var phase: Phase
        var buffer = ""
        var prefixStripped = false
    }

    private let transform: @Sendable (String) -> String
    private let hasCustomTransform: Bool
    private var textBlocks: [String: TextBlock] = [:]

    init(transform: @escaping @Sendable (String) -> String, hasCustomTransform: Bool) {
        self.transform = transform
        self.hasCustomTransform = hasCustomTransform
    }

    func process(_ chunk: LanguageModelV4StreamPart) -> [LanguageModelV4StreamPart] {
        switch chunk {
        case .textStart(let id, _):
            // Custom transforms need the whole text, so they buffer everything.
            textBlocks[id] = TextBlock(startEvent: chunk, phase: hasCustomTransform ? .buffering : .prefix)
            return []

        case .textDelta(let id, let delta, _):
            guard var block = textBlocks[id] else { return [chunk] }
            defer { textBlocks[id] = block }

            block.buffer += delta
            if block.phase == .buffering {
                return []
            }

            var output: [LanguageModelV4StreamPart] = []

            if block.phase == .prefix {
                if !block.buffer.isEmpty && !block.buffer.hasPrefix("`") {
                    block.phase = .streaming
                    output.append(block.startEvent)
                } else if block.buffer.hasPrefix("```") {
                    // Only strip the prefix once the fence line is complete.
                    if block.buffer.contains("\n") {
                        let range = NSRange(block.buffer.startIndex..., in: block.buffer)
                        if let match = completeFencePrefixPattern.firstMatch(in: block.buffer, range: range),
                           let matchRange = Range(match.range, in: block.buffer) {
                            block.buffer = String(block.buffer[matchRange.upperBound...])
                            block.prefixStripped = true
                        }
                        block.phase = .streaming
                        output.append(block.startEvent)
                    }
                } else if block.buffer.count >= 3 {
                    block.phase = .streaming
                    output.append(block.startEvent)
                }
            }

            // Stream content while retaining anything that could still become
            // trailing whitespace or a markdown fence suffix.
            if block.phase == .streaming {
                let suffixStart = potentialSuffixStart(block.buffer)
                let toStream = String(block.buffer[..<suffixStart])
                block.buffer = String(block.buffer[suffixStart...])
                if !toStream.isEmpty {
                    output.append(.textDelta(id: id, delta: toStream, providerMetadata: nil))
                }
            }
            return output

        case .textEnd(let id, _, _):
            guard let block = textBlocks.removeValue(forKey: id) else { return [chunk] }

            var output: [LanguageModelV4StreamPart] = []
            if block.phase == .prefix || block.phase == .buffering {
                output.append(block.startEvent)
            }

            let remaining: String
            switch block.phase {
            case .buffering:
                remaining = transform(block.buffer)
            case .prefix where !block.prefixStripped:
                // No text has streamed yet, so the full transform is safe.
                remaining = transform(block.buffer)
            default:
                // Earlier text already streamed: only strip the suffix, since trimming
                // the start would remove valid leading whitespace at the stream boundary.
                remaining = stripMarkdownCodeFenceSuffix(block.buffer)
            }

            if !remaining.isEmpty {
                output.append(.textDelta(id: id, delta: remaining, providerMetadata: nil))
            }
            output.append(chunk)
            return output

        default:
            return [chunk]
        }
    }
}
