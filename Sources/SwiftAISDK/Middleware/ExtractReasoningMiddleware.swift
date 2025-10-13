/**
 Extract an XML-tagged reasoning section from the generated text and exposes it
 as a `reasoning` property on the result.

 Port of `@ai-sdk/ai/src/middleware/extract-reasoning-middleware.ts`.

 This middleware scans text content for XML tags (e.g., `<thinking>...</thinking>`)
 and extracts the content as reasoning, removing it from the text content.

 **Note**: Full tests pending Block E implementation (requires `generateText()` and `streamText()` functions).
 See upstream tests: `extract-reasoning-middleware.test.ts`
 */

import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Configuration for extracting reasoning from text.
 */
public struct ExtractReasoningOptions: Sendable {
    /// The name of the XML tag to extract reasoning from (e.g., "thinking").
    public let tagName: String

    /// The separator to use between reasoning and text sections (default: "\n").
    public let separator: String

    /// Whether to start with reasoning tokens (default: false).
    /// If true, assumes the text starts inside a reasoning tag.
    public let startWithReasoning: Bool

    public init(
        tagName: String,
        separator: String = "\n",
        startWithReasoning: Bool = false
    ) {
        self.tagName = tagName
        self.separator = separator
        self.startWithReasoning = startWithReasoning
    }
}

/**
 Creates a middleware that extracts reasoning from XML tags in text content.

 - Parameter options: Configuration for reasoning extraction.
 - Returns: A middleware that extracts reasoning from text.

 Example usage:
 ```swift
 let model = wrapLanguageModel(
     model: baseModel,
     middleware: extractReasoningMiddleware(
         options: ExtractReasoningOptions(tagName: "thinking")
     )
 )
 ```
 */
public func extractReasoningMiddleware(options: ExtractReasoningOptions) -> LanguageModelV3Middleware {
    let openingTag = "<\(options.tagName)>"
    let closingTag = "</\(options.tagName)>"

    return LanguageModelV3Middleware(
        middlewareVersion: "v3",
        wrapGenerate: { doGenerate, _, _, _ in
            let result = try await doGenerate()

            var transformedContent: [LanguageModelV3Content] = []

            for content in result.content {
                // Only process text content
                guard case .text(let textPart) = content else {
                    transformedContent.append(content)
                    continue
                }

                let text = options.startWithReasoning ? openingTag + textPart.text : textPart.text

                // Create regex pattern for matching tags
                let pattern = "\(NSRegularExpression.escapedPattern(for: openingTag))(.*?)\(NSRegularExpression.escapedPattern(for: closingTag))"
                guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
                    transformedContent.append(content)
                    continue
                }

                let nsText = text as NSString
                let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))

                if matches.isEmpty {
                    transformedContent.append(content)
                    continue
                }

                // Extract reasoning text from all matches
                let reasoningText = matches.compactMap { match -> String? in
                    guard match.numberOfRanges > 1 else { return nil }
                    let captureRange = match.range(at: 1)
                    return nsText.substring(with: captureRange)
                }.joined(separator: options.separator)

                // Remove reasoning tags from text
                var textWithoutReasoning = text
                for match in matches.reversed() {
                    let matchRange = match.range
                    let beforeMatch = nsText.substring(to: matchRange.location)
                    let afterMatch = nsText.substring(from: matchRange.location + matchRange.length)

                    let needsSeparator = !beforeMatch.isEmpty && !afterMatch.isEmpty
                    textWithoutReasoning = beforeMatch + (needsSeparator ? options.separator : "") + afterMatch
                }

                // Add reasoning content first
                transformedContent.append(.reasoning(LanguageModelV3Reasoning(
                    text: reasoningText,
                    providerMetadata: textPart.providerMetadata
                )))

                // Add text content (with reasoning removed)
                transformedContent.append(.text(LanguageModelV3Text(
                    text: textWithoutReasoning,
                    providerMetadata: textPart.providerMetadata
                )))
            }

            return LanguageModelV3GenerateResult(
                content: transformedContent,
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

            // State tracking for reasoning extraction per text ID
            actor ReasoningExtractionState {
                var extractions: [String: ExtractionState] = [:]

                struct ExtractionState {
                    var isFirstReasoning: Bool = true
                    var isFirstText: Bool = true
                    var afterSwitch: Bool = false
                    var isReasoning: Bool
                    var buffer: String = ""
                    var idCounter: Int = 0
                    let textId: String
                }

                func getOrCreate(id: String, startWithReasoning: Bool) -> ExtractionState {
                    if let existing = extractions[id] {
                        return existing
                    }
                    let state = ExtractionState(
                        isReasoning: startWithReasoning,
                        textId: id
                    )
                    extractions[id] = state
                    return state
                }

                func update(id: String, _ updater: (inout ExtractionState) -> Void) {
                    guard var state = extractions[id] else { return }
                    updater(&state)
                    extractions[id] = state
                }
            }

            let state = ReasoningExtractionState()

            let transformedStream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { continuation in
                Task {
                    var delayedTextStart: LanguageModelV3StreamPart?

                    do {
                        for try await chunk in result.stream {
                            // Handle delayed text-start (don't send before reasoning-start)
                            // https://github.com/vercel/ai/issues/7774
                            if case .textStart = chunk {
                                delayedTextStart = chunk
                                continue
                            }

                            if case .textEnd = chunk, delayedTextStart != nil {
                                continuation.yield(delayedTextStart!)
                                delayedTextStart = nil
                            }

                            // Only process text-delta
                            guard case .textDelta(let id, let delta, let providerMetadata) = chunk else {
                                continuation.yield(chunk)
                                continue
                            }

                            // Get or create extraction state
                            var activeExtraction = await state.getOrCreate(id: id, startWithReasoning: options.startWithReasoning)
                            activeExtraction.buffer += delta

                            // Helper to publish text
                            func publish(text: String) {
                                guard !text.isEmpty else { return }

                                let prefix: String
                                if activeExtraction.afterSwitch {
                                    if activeExtraction.isReasoning {
                                        prefix = !activeExtraction.isFirstReasoning ? options.separator : ""
                                    } else {
                                        prefix = !activeExtraction.isFirstText ? options.separator : ""
                                    }
                                } else {
                                    prefix = ""
                                }

                                if activeExtraction.isReasoning &&
                                   (activeExtraction.afterSwitch || activeExtraction.isFirstReasoning) {
                                    continuation.yield(.reasoningStart(
                                        id: "reasoning-\(activeExtraction.idCounter)",
                                        providerMetadata: providerMetadata
                                    ))
                                }

                                if activeExtraction.isReasoning {
                                    continuation.yield(.reasoningDelta(
                                        id: "reasoning-\(activeExtraction.idCounter)",
                                        delta: prefix + text,
                                        providerMetadata: providerMetadata
                                    ))
                                } else {
                                    if let delayed = delayedTextStart {
                                        continuation.yield(delayed)
                                        delayedTextStart = nil
                                    }
                                    continuation.yield(.textDelta(
                                        id: activeExtraction.textId,
                                        delta: prefix + text,
                                        providerMetadata: providerMetadata
                                    ))
                                }

                                activeExtraction.afterSwitch = false

                                if activeExtraction.isReasoning {
                                    activeExtraction.isFirstReasoning = false
                                } else {
                                    activeExtraction.isFirstText = false
                                }
                            }

                            // Process buffer for tags
                            while true {
                                let nextTag = activeExtraction.isReasoning ? closingTag : openingTag

                                let startIndex = getPotentialStartIndex(
                                    text: activeExtraction.buffer,
                                    searchedText: nextTag
                                )

                                // No opening or closing tag found, publish the buffer
                                guard let startIndex = startIndex else {
                                    publish(text: activeExtraction.buffer)
                                    activeExtraction.buffer = ""
                                    break
                                }

                                // Publish text before the tag
                                let textBeforeTag = String(activeExtraction.buffer.prefix(startIndex))
                                publish(text: textBeforeTag)

                                let foundFullMatch = startIndex + nextTag.count <= activeExtraction.buffer.count

                                if foundFullMatch {
                                    // Remove the tag from buffer
                                    let tagEndIndex = activeExtraction.buffer.index(
                                        activeExtraction.buffer.startIndex,
                                        offsetBy: startIndex + nextTag.count
                                    )
                                    activeExtraction.buffer = String(activeExtraction.buffer[tagEndIndex...])

                                    // Reasoning part finished
                                    if activeExtraction.isReasoning {
                                        continuation.yield(.reasoningEnd(
                                            id: "reasoning-\(activeExtraction.idCounter)",
                                            providerMetadata: providerMetadata
                                        ))
                                        activeExtraction.idCounter += 1
                                    }

                                    activeExtraction.isReasoning.toggle()
                                    activeExtraction.afterSwitch = true
                                } else {
                                    // Partial match, keep buffer from startIndex
                                    let bufferStartIndex = activeExtraction.buffer.index(
                                        activeExtraction.buffer.startIndex,
                                        offsetBy: startIndex
                                    )
                                    activeExtraction.buffer = String(activeExtraction.buffer[bufferStartIndex...])
                                    break
                                }
                            }

                            // Update state
                            await state.update(id: id) { $0 = activeExtraction }
                        }

                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            }

            return LanguageModelV3StreamResult(
                stream: transformedStream,
                request: result.request,
                response: result.response
            )
        }
    )
}
