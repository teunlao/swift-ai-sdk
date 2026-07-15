# Provider: OpenAI-compatible

- Audited against upstream commit: `c8d2726ae045a28142cb46df5e41cdd51d8dcc71`
- Status: verified/current; Chat, Completion, Embedding, Image, provider
  factory, option-key utilities, typed errors, tools, and tracked upstream
  fixtures are audited at the pinned baseline.
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
- [x] Provider option key conversion, warning emission, metadata-key
  selection, and V4 body precedence match upstream: provider extensions may
  override standard settings, while SDK-owned messages, reasoning, verbosity,
  tools, and tool choice remain authoritative.
- [x] Non-streaming V4 output maps text, reasoning, tool calls, finish reason,
  response metadata, warnings, provider metadata, detailed usage, custom
  `convertUsage` over the complete loose usage object, reasoning fallback, and
  Google thought signatures.
- [x] Response thought signatures follow upstream truthiness in generate and
  stream paths: an empty signature does not create empty provider metadata.
- [x] Non-streaming Chat rejects malformed tool calls at the response boundary:
  `function`, `function.name`, and `function.arguments` are required exactly as
  in the audited upstream response schema instead of being dropped or defaulted
  after decoding.
- [x] Chat response roles are validated at the decode boundary: non-streaming
  responses allow only `assistant` when a role is present, while streaming
  deltas preserve upstream compatibility with both `assistant` and the empty
  role used by some providers. Other role values produce response-validation
  errors instead of being ignored.
- [x] Streaming V4 output preserves reasoning-before-text lifecycle ordering,
  late tool names, missing tool-call indexes, thought signatures, raw chunks,
  error chunks, usage, finish metadata, and cancellation. Tool calls finalize
  once during stream flush so a parsable argument prefix is not executed as a
  truncated call.
- [x] Streaming tool-call deltas require the upstream `function` object at the
  response boundary. Malformed deltas produce per-chunk validation errors and
  do not poison pending tracker state or terminate an otherwise valid stream at
  flush. Unmodeled tool-call fields are ignored in both generate and stream
  responses, matching the upstream loose-object schemas.
- [x] Chat and Completion stream unions validate data first and then the
  configured provider error schema. The same typed error configuration now
  owns HTTP and SSE validation, including custom Baseten, Cerebras, Fireworks,
  and xAI shapes; raw V3 and inner V4 Completion error payload semantics remain
  intact.
- [x] The shared tracker still forwards an upstream trailing empty argument
  delta while emitting exactly one final tool call.
- [x] Existing OpenAI-compatible V3 Chat behavior remains covered by the full
  provider test target, including V3-specific stream ids, initial empty tool
  deltas, provider-option handling, and error payloads.
- [x] The four upstream xAI Chat fixtures are copied byte-for-byte into tracked
  test resources. Generate tests cover both complete responses; stream tests
  consume all 344 text and 230 tool-call payloads and assert reasoning, text,
  tool calls, lifecycle ordering, usage, unknown usage keys, and metadata.
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
- [x] V4 Completion validates the full audited response schemas: generate
  requires `choices[].text`, `choices[].finish_reason`, and all three usage
  counters when usage is present; stream additionally requires each choice
  index. Invalid stream chunks emit errors without contaminating later valid
  text, finish reason, or usage.
- [x] Streaming V4 Completion preserves text lifecycle ordering, including an
  initial empty delta, raw chunks, inner provider error payloads, unparsable
  error/finish events, and usage.
- [x] Existing OpenAI-compatible V3 Completion behavior remains covered by the
  provider test target while retaining its V3-specific warnings and stream
  behavior.
- [x] `createOpenAICompatible(settings:)` routes `embeddingModel` and
  `textEmbeddingModel` directly to `OpenAICompatibleEmbeddingModelV4`;
  Embedding no longer crosses a V3-to-V4 adapter. The public V3 and native V4
  facades share one provider-owned transport core.
- [x] Native V4 Embedding matches upstream provider-option ordering across the
  deprecated `openai-compatible`, canonical `openaiCompatible`, and raw
  provider namespaces, including both deprecation warning forms.
- [x] V4 Embedding request and response mapping covers model/input,
  `encoding_format`, dimensions, user, merged headers, embeddings, usage,
  provider metadata, raw response information, configurable call limits, and
  parallel-call capability.
- [x] Embedding response validation requires `usage.prompt_tokens` whenever a
  usage object is present, matching the upstream response schema instead of
  silently treating malformed usage as absent.
- [x] Existing OpenAI-compatible V3 Embedding request precedence and warning
  behavior remain covered by the provider test target.
- [x] `createOpenAICompatible(settings:)` routes Image models directly to
  `OpenAICompatibleImageModelV4`; Image no longer crosses the provider-local
  V3-to-V4 adapter. The public V3 and native V4 facades share one
  provider-owned transport core while preserving the V3 JSON-generation
  request contract.
- [x] Native V4 Image provider options use the base provider namespace, emit
  the upstream deprecation warning for raw hyphenated keys, prefer the
  canonical camel-case namespace, and keep `response_format: b64_json`
  authoritative for generation requests.
- [x] Native V4 Image editing uses `/images/edits` multipart requests for one or
  multiple binary, base64, or URL-backed images plus an optional mask. Form
  fields, array-key behavior, downloaded media types, response images,
  timestamps, headers, and unsupported-setting warnings match the audited
  upstream contract.
- [x] Existing OpenAI-compatible V3 Image behavior remains covered by its model
  tests, including the legacy `openai` provider-options namespace, request
  shape, errors, headers, warnings, and response metadata.

## Audited source closure

| Upstream owner | Swift owner and evidence |
| --- | --- |
| `src/openai-compatible-provider.ts`, `src/version.ts`, `src/index.ts` | `OpenAICompatibleProvider.swift`, `OpenAICompatibleVersion.swift`, public SwiftPM target surface, provider V3/V4 tests |
| `src/openai-compatible-error.ts`, `src/utils/to-camel-case.ts` | `OpenAICompatibleError.swift`, `OpenAICompatibleProviderOptionKeys.swift`, custom stream-error and option-key tests |
| `src/chat/**` including all four fixtures | `Chat/**`, tracked `Tests/OpenAICompatibleProviderTests/Fixtures/**`, converter/options/tools/model/fixture tests |
| `src/completion/**` | `Completion/**`, V3 and native V4 Completion tests |
| `src/embedding/**` | `Embedding/**`, V3 and native V4 Embedding tests |
| `src/image/**` | `Image/**`, V3 and native V4 generation/edit tests |

## Swift adaptations (not gaps)

- TypeScript's symbol-based `WORKFLOW_SERIALIZE` / `WORKFLOW_DESERIALIZE`
  methods are not applicable because Swift has no corresponding workflow model
  dispatch protocol. The shared `serializeModelOptions` policy is implemented
  and tested in `AISDKProviderUtils`; no provider hook exists to attach here.
- The upstream provider interface declares an optional partial Chat config on
  `languageModel`, but its concrete factory accepts only the model id and
  ignores extra JavaScript arguments. Swift does not expose an inert argument.
- Swift uses `Data`, `URL`, typed content enums, and `RawRepresentable` model
  ids in place of JavaScript `Uint8Array`, loose unions, callable providers,
  and generic string-literal ids.
- For a custom typed stream error, Swift applies the configured
  `errorToMessage`; the default OpenAI-compatible error remains identical to
  upstream while providers whose `error` field is a string retain a usable
  message. This contract is recorded in `plan/design-decisions.md`.

## Known gaps / TODO

- None known for the audited upstream baseline.

## Evidence

- Upstream Chat model and tests:
  `external/vercel-ai-sdk/packages/openai-compatible/src/chat/**`.
- Upstream provider factory:
  `external/vercel-ai-sdk/packages/openai-compatible/src/openai-compatible-provider.ts`.
- Upstream Completion model and tests:
  `external/vercel-ai-sdk/packages/openai-compatible/src/completion/**`.
- Upstream Embedding model and tests:
  `external/vercel-ai-sdk/packages/openai-compatible/src/embedding/**`.
- Upstream Image model and tests:
  `external/vercel-ai-sdk/packages/openai-compatible/src/image/**`.
- Swift Chat model:
  `Sources/OpenAICompatibleProvider/Chat/OpenAICompatibleChatLanguageModel.swift`.
- Swift Completion model and prompt conversion:
  `Sources/OpenAICompatibleProvider/Completion/OpenAICompatibleCompletionLanguageModel.swift`
  and
  `Sources/OpenAICompatibleProvider/Completion/ConvertToOpenAICompatibleCompletionPrompt.swift`.
- Swift Embedding model:
  `Sources/OpenAICompatibleProvider/Embedding/OpenAICompatibleEmbeddingModel.swift`.
- Swift Image model:
  `Sources/OpenAICompatibleProvider/Image/OpenAICompatibleImageModel.swift`.
- Swift prompt/tool conversion:
  `Sources/OpenAICompatibleProvider/Chat/ConvertToOpenAICompatibleChatMessages.swift`
  and `Sources/OpenAICompatibleProvider/Chat/OpenAICompatiblePrepareTools.swift`.
- Swift provider factory:
  `Sources/OpenAICompatibleProvider/OpenAICompatibleProvider.swift`.
- Swift error and provider-option owners:
  `Sources/OpenAICompatibleProvider/OpenAICompatibleError.swift` and
  `Sources/OpenAICompatibleProvider/OpenAICompatibleProviderOptionKeys.swift`.
- Exact tracked upstream fixtures and tests:
  `Tests/OpenAICompatibleProviderTests/Fixtures/**` and
  `Tests/OpenAICompatibleProviderTests/OpenAICompatibleChatFixtureTests.swift`.
- Swift V4 tests:
  `Tests/OpenAICompatibleProviderTests/OpenAICompatibleProviderV4Tests.swift`
  and
  `Tests/OpenAICompatibleProviderTests/OpenAICompatibleChatMessagesConverterV4Tests.swift`
  and
  `Tests/OpenAICompatibleProviderTests/OpenAICompatibleCompletionLanguageModelV4Tests.swift`
  and
  `Tests/OpenAICompatibleProviderTests/OpenAICompatibleEmbeddingModelV4Tests.swift`
  and
  `Tests/OpenAICompatibleProviderTests/OpenAICompatibleImageModelV4Tests.swift`.
- Additional boundary tests:
  `Tests/OpenAICompatibleProviderTests/OpenAICompatiblePrepareToolsV4Tests.swift`,
  `Tests/OpenAICompatibleProviderTests/OpenAICompatibleProviderOptionKeysTests.swift`,
  `Tests/OpenAICompatibleProviderTests/OpenAICompatibleCustomStreamErrorTests.swift`,
  and
  `Tests/OpenAICompatibleProviderTests/OpenAICompatibleThoughtSignatureV4Tests.swift`.

## Validation

- `AGENT=1 swift test --filter OpenAICompatibleProviderTests` passed 185 tests
  in 18 suites.
- `AGENT=1 swift test --filter OpenAICompatibleProviderV4Tests` is included in
  that target pass with 15 tests.
- `AGENT=1 swift test --filter OpenAICompatibleChatMessagesConverterV4Tests`
  passed 5 tests.
- `AGENT=1 swift test --filter OpenAICompatibleCompletionLanguageModelV4Tests`
  passed 8 tests.
- `AGENT=1 swift test --filter OpenAICompatibleEmbeddingModelV4Tests` passed 4
  tests.
- `AGENT=1 swift test --filter OpenAICompatibleImageModel` passed 13 tests in
  2 suites.
- The same provider-target pass includes 4 exact-fixture tests, 4 tool
  preparation tests, 3 option-key tests, 2 custom stream-error tests, and 1
  empty thought-signature test.
- `AGENT=1 swift test --filter BasetenProviderTests`,
  `CerebrasProviderTests`, `FireworksProviderTests`, and `XAIProviderTests`
  passed 26, 9, 3, and 163 tests respectively after their typed error
  configurations were migrated.
- `cmp` confirmed all four tracked xAI fixtures are byte-identical to the
  pinned upstream checkout.
- `swift build` passed.
- `AGENT=1 swift test` passed all 4105 tests in 469 suites, including the MCP
  transport suites that had been timing-sensitive in an earlier audit slice.
- `node .agents/skills/swift-ai-sdk-upstream/scripts/scan-upstream.js --out
  .upstream/current` reports `openai-compatible | provider | P0 | verified |
  current` at commit `c8d2726ae045a28142cb46df5e41cdd51d8dcc71`.
- `git diff --check` passed.
