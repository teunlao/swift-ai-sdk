# Provider: OpenAI-compatible

- Audited against upstream commit: `c8d2726ae045a28142cb46df5e41cdd51d8dcc71`
- Status: partial/current; Chat and Completion are native V4, while Embedding
  and Image still use the provider-local adapter rail.
- Upstream package: `external/vercel-ai-sdk/packages/openai-compatible/src/**`
- Swift implementation: `Sources/OpenAICompatibleProvider/**`

## What is verified (checked + tested)

- [x] `createOpenAICompatible(settings:)` routes `languageModel` and
  `chatModel` directly to `OpenAICompatibleChatLanguageModelV4`; Chat no
  longer crosses a V3-to-V4 adapter.
- [x] `createOpenAICompatibleProvider(settings:)` and the public
  `OpenAICompatibleChatLanguageModel` V3 facade remain available. Both Chat
  facades delegate to one provider-owned transport core so request and stream
  behavior cannot drift between duplicate implementations.
- [x] Native V4 prompt conversion covers system/user metadata, inline and URL
  images, WAV/MP3 audio, PDF files, text files, assistant reasoning, function
  tool calls/results, approval responses, and execution-denied results.
- [x] V4 Chat request mapping covers top-level `reasoning` to
  `reasoning_effort`, function tools and tool choice, raw provider options,
  canonical camel-case provider options, request transforms, headers, and
  `supportedUrls`.
- [x] Non-streaming V4 output maps text, reasoning, tool calls, finish reason,
  response metadata, warnings, provider metadata, detailed usage, custom
  `convertUsage` over the complete loose usage object, reasoning fallback, and
  Google thought signatures.
- [x] Streaming V4 output preserves reasoning-before-text lifecycle ordering,
  late tool names, missing tool-call indexes, thought signatures, raw chunks,
  error chunks, usage, finish metadata, and cancellation. Tool calls finalize
  once during stream flush so a parsable argument prefix is not executed as a
  truncated call.
- [x] The shared tracker still forwards an upstream trailing empty argument
  delta while emitting exactly one final tool call.
- [x] Existing OpenAI-compatible V3 Chat behavior remains covered by the full
  provider test target, including V3-specific stream ids, initial empty tool
  deltas, provider-option handling, and error payloads.
- [x] `createOpenAICompatible(settings:)` routes Completion models directly to
  `OpenAICompatibleCompletionLanguageModelV4`; Completion no longer crosses a
  V3-to-V4 adapter. The public V3 Completion facade and native V4 facade share
  one provider-owned transport core.
- [x] Native V4 Completion prompt and request mapping covers system/user/
  assistant text, unsupported role failures, raw and canonical camel-case
  provider options, raw-key deprecation warnings, canonical-key precedence,
  unsupported-setting warnings, request headers, and direct-model
  `supportedUrls` configuration.
- [x] Non-streaming V4 Completion maps text, finish reason, response metadata,
  detailed usage, and the parsed provider usage object exposed through
  `usage.raw`.
- [x] Streaming V4 Completion preserves text lifecycle ordering, including an
  initial empty delta, raw chunks, inner provider error payloads, unparsable
  error/finish events, and usage.
- [x] Existing OpenAI-compatible V3 Completion behavior remains covered by the
  provider test target while retaining its V3-specific warnings and stream
  behavior.
- [x] The V4 provider factory still exposes Embedding,
  `textEmbeddingModel`, and Image through their existing adapters.

## Known gaps / TODO

- [ ] Migrate OpenAI-compatible Embedding and Image from the provider-local V3
  adapter rail to native V4 implementations.
- [ ] Full upstream fixture parity for every Chat, Completion, Embedding,
  Image, and error path is not claimed by this tracker entry.

## Evidence

- Upstream Chat model and tests:
  `external/vercel-ai-sdk/packages/openai-compatible/src/chat/**`.
- Upstream provider factory:
  `external/vercel-ai-sdk/packages/openai-compatible/src/openai-compatible-provider.ts`.
- Upstream Completion model and tests:
  `external/vercel-ai-sdk/packages/openai-compatible/src/completion/**`.
- Swift Chat model:
  `Sources/OpenAICompatibleProvider/Chat/OpenAICompatibleChatLanguageModel.swift`.
- Swift Completion model and prompt conversion:
  `Sources/OpenAICompatibleProvider/Completion/OpenAICompatibleCompletionLanguageModel.swift`
  and
  `Sources/OpenAICompatibleProvider/Completion/ConvertToOpenAICompatibleCompletionPrompt.swift`.
- Swift prompt/tool conversion:
  `Sources/OpenAICompatibleProvider/Chat/ConvertToOpenAICompatibleChatMessages.swift`
  and `Sources/OpenAICompatibleProvider/Chat/OpenAICompatiblePrepareTools.swift`.
- Swift provider factory:
  `Sources/OpenAICompatibleProvider/OpenAICompatibleProvider.swift`.
- Swift V4 tests:
  `Tests/OpenAICompatibleProviderTests/OpenAICompatibleProviderV4Tests.swift`
  and
  `Tests/OpenAICompatibleProviderTests/OpenAICompatibleChatMessagesConverterV4Tests.swift`
  and
  `Tests/OpenAICompatibleProviderTests/OpenAICompatibleCompletionLanguageModelV4Tests.swift`.

## Validation

- `AGENT=1 swift test --filter OpenAICompatibleProviderTests` passed 154 tests
  in 11 suites.
- `AGENT=1 swift test --filter OpenAICompatibleProviderV4Tests` passed 9 tests.
- `AGENT=1 swift test --filter OpenAICompatibleChatMessagesConverterV4Tests`
  passed 2 tests.
- `AGENT=1 swift test --filter OpenAICompatibleCompletionLanguageModelV4Tests`
  passed 6 tests.
- `AGENT=1 swift test --filter StreamingToolCallTrackerTests` passed 15 tests.
- `swift build` passed.
- `AGENT=1 swift test` passed all 4074 tests in 462 suites.
