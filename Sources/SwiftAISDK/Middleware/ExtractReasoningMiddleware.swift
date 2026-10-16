/**
 Extracts a delimited reasoning section from the generated text and exposes it
 as reasoning content.

 Port of `@ai-sdk/ai/src/middleware/extract-reasoning-middleware.ts`.
 */

import Foundation
import AISDKProvider
import AISDKProviderUtils

/// Configuration for `extractReasoningMiddleware`.
public struct ExtractReasoningOptions: Sendable {
    /// The literal delimiters around a reasoning section.
    public struct TagName: Sendable, Equatable {
        public let opening: String
        public let closing: String

        /// An XML tag name without angle brackets: `think` delimits `<think>…</think>`.
        public init(_ tagName: String) {
            self.opening = "<\(tagName)>"
            self.closing = "</\(tagName)>"
        }

        /// Literal opening and closing delimiters, for formats such as Gemma's thought channel.
        /// - Throws: `InvalidArgumentError` when either delimiter is empty.
        public init(opening: String, closing: String) throws {
            guard !opening.isEmpty, !closing.isEmpty else {
                throw InvalidArgumentError(
                    parameter: "tagName",
                    value: .object(["opening": .string(opening), "closing": .string(closing)]),
                    message: "Reasoning delimiters must not be empty."
                )
            }
            self.opening = opening
            self.closing = closing
        }
    }

    /// The delimiters of a reasoning section.
    public let tagName: TagName

    /// The separator to use between reasoning and text sections (default: "\n").
    public let separator: String

    /// Whether the text starts inside a reasoning section, without an opening delimiter (default: false).
    public let startWithReasoning: Bool

    public init(
        tagName: TagName,
        separator: String = "\n",
        startWithReasoning: Bool = false
    ) {
        self.tagName = tagName
        self.separator = separator
        self.startWithReasoning = startWithReasoning
    }

    /// - Parameter tagName: An XML tag name without angle brackets.
    public init(
        tagName: String,
        separator: String = "\n",
        startWithReasoning: Bool = false
    ) {
        self.init(tagName: TagName(tagName), separator: separator, startWithReasoning: startWithReasoning)
    }
}

/**
 Creates a middleware that extracts reasoning sections from text content.

 Example usage:
 ```swift
 let model = wrapLanguageModel(
     model: baseModel,
     middleware: extractReasoningMiddleware(
         options: ExtractReasoningOptions(tagName: "think")
     )
 )
 ```
 */
public func extractReasoningMiddleware(options: ExtractReasoningOptions) -> LanguageModelV4Middleware {
    LanguageModelV4Middleware(
        wrapGenerate: { doGenerate, _, _, _ in
            let result = try await doGenerate()

            var content: [LanguageModelV4Content] = []
            for part in result.content {
                guard case .text(let text) = part,
                      let extracted = extractReasoning(from: text.text, options: options)
                else {
                    content.append(part)
                    continue
                }
                content.append(.reasoning(LanguageModelV4Reasoning(text: extracted.reasoning)))
                content.append(.text(LanguageModelV4Text(text: extracted.text)))
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
            let extractor = ReasoningStreamExtractor<LanguageModelV4StreamPart>(
                options: options,
                parts: ReasoningStreamParts(
                    classify: { part in
                        switch part {
                        case .textStart(let id, _): return .textStart(id: id)
                        case .textDelta(let id, let delta, _): return .textDelta(id: id, delta: delta)
                        case .textEnd(let id, _, _): return .textEnd(id: id)
                        default: return .other
                        }
                    },
                    reasoningStart: { .reasoningStart(id: $0, providerMetadata: nil) },
                    reasoningDelta: { .reasoningDelta(id: $0, delta: $1, providerMetadata: nil) },
                    reasoningEnd: { .reasoningEnd(id: $0, providerMetadata: nil) },
                    textDelta: { .textDelta(id: $0, delta: $1, providerMetadata: nil) }
                )
            )
            return LanguageModelV4StreamResult(
                stream: pipeMiddlewareStream(result.stream) { extractor.process($0) },
                request: result.request,
                response: result.response
            )
        }
    )
}

/// Creates a V3 middleware that extracts reasoning sections from text content.
public func extractReasoningMiddleware(options: ExtractReasoningOptions) -> LanguageModelV3Middleware {
    LanguageModelV3Middleware(
        middlewareVersion: "v3",
        wrapGenerate: { doGenerate, _, _, _ in
            let result = try await doGenerate()

            var content: [LanguageModelV3Content] = []
            for part in result.content {
                guard case .text(let text) = part,
                      let extracted = extractReasoning(from: text.text, options: options)
                else {
                    content.append(part)
                    continue
                }
                content.append(.reasoning(LanguageModelV3Reasoning(text: extracted.reasoning)))
                content.append(.text(LanguageModelV3Text(text: extracted.text)))
            }

            return LanguageModelV3GenerateResult(
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
            let extractor = ReasoningStreamExtractor<LanguageModelV3StreamPart>(
                options: options,
                parts: ReasoningStreamParts(
                    classify: { part in
                        switch part {
                        case .textStart(let id, _): return .textStart(id: id)
                        case .textDelta(let id, let delta, _): return .textDelta(id: id, delta: delta)
                        case .textEnd(let id, _): return .textEnd(id: id)
                        default: return .other
                        }
                    },
                    reasoningStart: { .reasoningStart(id: $0, providerMetadata: nil) },
                    reasoningDelta: { .reasoningDelta(id: $0, delta: $1, providerMetadata: nil) },
                    reasoningEnd: { .reasoningEnd(id: $0, providerMetadata: nil) },
                    textDelta: { .textDelta(id: $0, delta: $1, providerMetadata: nil) }
                )
            )
            return LanguageModelV3StreamResult(
                stream: pipeMiddlewareStream(result.stream) { extractor.process($0) },
                request: result.request,
                response: result.response
            )
        }
    )
}

// MARK: - Generate

/// Splits `text` into reasoning and the remaining text, or returns `nil` when it holds no complete section.
private func extractReasoning(
    from rawText: String,
    options: ExtractReasoningOptions
) -> (reasoning: String, text: String)? {
    let opening = options.tagName.opening
    let closing = options.tagName.closing
    let text = options.startWithReasoning ? opening + rawText : rawText

    // Delimiters are literal strings, including regex metacharacters such as `|`.
    let pattern = NSRegularExpression.escapedPattern(for: opening)
        + "(.*?)"
        + NSRegularExpression.escapedPattern(for: closing)
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
        return nil
    }

    let nsText = text as NSString
    let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
    if matches.isEmpty {
        return nil
    }

    let reasoning = matches
        .map { nsText.substring(with: $0.range(at: 1)) }
        .joined(separator: options.separator)

    var textWithoutReasoning = text
    for match in matches.reversed() {
        let current = textWithoutReasoning as NSString
        let beforeMatch = current.substring(to: match.range.location)
        let afterMatch = current.substring(from: match.range.location + match.range.length)
        let separator = !beforeMatch.isEmpty && !afterMatch.isEmpty ? options.separator : ""
        textWithoutReasoning = beforeMatch + separator + afterMatch
    }

    return (reasoning, textWithoutReasoning)
}

// MARK: - Stream

/// The text stream parts the extractor reads, independent of the specification version.
private enum TextStreamPartKind {
    case textStart(id: String)
    case textDelta(id: String, delta: String)
    case textEnd(id: String)
    case other
}

/// How the extractor reads and builds stream parts of one specification version.
private struct ReasoningStreamParts<Part> {
    let classify: @Sendable (Part) -> TextStreamPartKind
    let reasoningStart: @Sendable (_ id: String) -> Part
    let reasoningDelta: @Sendable (_ id: String, _ delta: String) -> Part
    let reasoningEnd: @Sendable (_ id: String) -> Part
    let textDelta: @Sendable (_ id: String, _ delta: String) -> Part
}

/// The upstream `TransformStream` state of one stream. Its single pump task
/// (`pipeMiddlewareStream`) is the only caller of `process`.
private final class ReasoningStreamExtractor<Part>: @unchecked Sendable {
    private struct Extraction {
        var isFirstReasoning = true
        var isFirstText = true
        var afterSwitch = false
        var isReasoning: Bool
        var buffer = ""
        var reasoningId: String?
        let textId: String
    }

    private let opening: String
    private let closing: String
    private let separator: String
    private let startWithReasoning: Bool
    private let parts: ReasoningStreamParts<Part>

    private var extractions: [String: Extraction] = [:]
    private var reasoningIdCounter = 0
    // `text-start` is held until its text is published, so it never precedes
    // `reasoning-start` (https://github.com/vercel/ai/issues/7774).
    private var delayedTextStarts: [String: Part] = [:]

    init(options: ExtractReasoningOptions, parts: ReasoningStreamParts<Part>) {
        self.opening = options.tagName.opening
        self.closing = options.tagName.closing
        self.separator = options.separator
        self.startWithReasoning = options.startWithReasoning
        self.parts = parts
    }

    func process(_ chunk: Part) -> [Part] {
        var output: [Part] = []

        switch parts.classify(chunk) {
        case .other:
            return [chunk]

        case .textStart(let id):
            delayedTextStarts[id] = chunk
            return []

        case .textEnd(let id):
            guard var extraction = extractions[id] else {
                flushDelayedTextStart(id, into: &output)
                output.append(chunk)
                return output
            }
            publish(extraction.buffer, &extraction, into: &output)
            extraction.buffer = ""
            extractions[id] = extraction

            flushDelayedTextStart(id, into: &output)
            output.append(chunk)
            return output

        case .textDelta(let id, let delta):
            var extraction = extractions[id] ?? Extraction(isReasoning: startWithReasoning, textId: id)
            extraction.buffer += delta

            while true {
                let nextTag = extraction.isReasoning ? closing : opening

                guard let startIndex = getPotentialStartIndex(text: extraction.buffer, searchedText: nextTag) else {
                    // no opening or closing tag found, publish the buffer
                    publish(extraction.buffer, &extraction, into: &output)
                    extraction.buffer = ""
                    break
                }

                let tagStart = extraction.buffer.index(extraction.buffer.startIndex, offsetBy: startIndex)
                publish(String(extraction.buffer[..<tagStart]), &extraction, into: &output)

                let afterTag = extraction.buffer.index(
                    tagStart,
                    offsetBy: nextTag.count,
                    limitedBy: extraction.buffer.endIndex
                )
                guard let afterTag else {
                    // partial tag at the end of the buffer: wait for more text
                    extraction.buffer = String(extraction.buffer[tagStart...])
                    break
                }

                extraction.buffer = String(extraction.buffer[afterTag...])

                if extraction.isReasoning {
                    // An empty reasoning block published no delta, so it still needs its start.
                    if extraction.isFirstReasoning {
                        output.append(parts.reasoningStart(reasoningId(&extraction)))
                    }
                    output.append(parts.reasoningEnd(reasoningId(&extraction)))
                    extraction.reasoningId = nil
                }

                extraction.isReasoning.toggle()
                extraction.afterSwitch = true
            }

            extractions[id] = extraction
            return output
        }
    }

    private func reasoningId(_ extraction: inout Extraction) -> String {
        if let id = extraction.reasoningId {
            return id
        }
        let id = "reasoning-\(reasoningIdCounter)"
        reasoningIdCounter += 1
        extraction.reasoningId = id
        return id
    }

    private func publish(_ text: String, _ extraction: inout Extraction, into output: inout [Part]) {
        guard !text.isEmpty else { return }

        let needsSeparator = extraction.afterSwitch
            && (extraction.isReasoning ? !extraction.isFirstReasoning : !extraction.isFirstText)
        let delta = (needsSeparator ? separator : "") + text

        if extraction.isReasoning {
            if extraction.afterSwitch || extraction.isFirstReasoning {
                output.append(parts.reasoningStart(reasoningId(&extraction)))
            }
            output.append(parts.reasoningDelta(reasoningId(&extraction), delta))
            extraction.isFirstReasoning = false
        } else {
            flushDelayedTextStart(extraction.textId, into: &output)
            output.append(parts.textDelta(extraction.textId, delta))
            extraction.isFirstText = false
        }
        extraction.afterSwitch = false
    }

    private func flushDelayedTextStart(_ id: String, into output: inout [Part]) {
        if let start = delayedTextStarts.removeValue(forKey: id) {
            output.append(start)
        }
    }
}
