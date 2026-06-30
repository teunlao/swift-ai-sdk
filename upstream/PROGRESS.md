# Upstream Parity Progress

This folder is the source of truth for “what is verified” vs “what is unknown” against a specific upstream commit.

Rules:
- Always tie statements to an upstream commit hash from `upstream/UPSTREAM.md`.
- Prefer provider parity work (prompt ↔ HTTP ↔ decode ↔ streaming) over core refactors.
- Keep docs short and actionable: checklists + links to Swift/upstream paths.

## Current priorities

1) Providers parity (tools, streaming, errors)
2) Core API parity only when blocked by providers
3) Docs updates only after behavior parity is green

## Current upstream intake snapshot

### 2026-06-30: `ai@7.0.8` / upstream `85a80fc6e71558717899e30c9f1fc0e9eb7d733d`

Scope: `intake:latest-main`.

Evidence:
- `external/vercel-ai-sdk` refreshed from upstream `main` to `85a80fc6e71558717899e30c9f1fc0e9eb7d733d`.
- `npm view ai version time.modified --json` reported `7.0.8`, modified `2026-06-30T04:05:57.112Z`.
- Generated local artifacts:
  - `.upstream/current/component-catalog.md`
  - `.upstream/refresh-2026-06-30/package-diff.md`
  - `.upstream/refresh-2026-06-30/work-queue.md`

Important interpretation:
- No component should be treated as `verified` against the current baseline until
  it is re-audited against `85a80fc6e71558717899e30c9f1fc0e9eb7d733d`.
- The previous baseline was `4891db8bfc583d3767831dac83439ac190c93cb0`
  from 2026-04-15. The current upstream package line is major-version newer
  across core and most providers (`ai` 7.x, `provider` 4.x,
  `provider-utils` 5.x, `openai` 4.x, `anthropic` 4.x).
- This pass refreshed intake artifacts only. It did not claim runtime parity,
  port behavior, or update provider-specific verification checklists.

Component scan summary:

| Priority | Status | Count | Components |
| --- | --- | ---: | --- |
| P0 | stale | 8 | `ai`, `provider`, `provider-utils`, `anthropic`, `gateway`, `google`, `google-vertex`, `openai` |
| P0 | mapped | 1 | `openai-compatible` has an intake tracking page but no audited commit |
| P1 | stale | 29 | Existing Swift provider targets with old audited commits |
| P1 | mapped | 3 | `baseten`, `moonshotai`, `open-responses` have Swift owners and intake tracking pages but no audited commit |
| P1 | unknown | 3 | `anthropic-aws`, `quiverai`, `voyage` are upstream provider packages with intake tracking pages but no Swift owner target |
| P2 | n/a | 5 | Framework packages: `angular`, `react`, `rsc`, `svelte`, `vue` |
| P3 | n/a | 20 | Upstream tooling/internal packages, including new `harness*`, `sandbox-*`, `policy-opa`, `tui`, `workflow-harness` |

Added upstream packages since the previous catalog:
- Runtime provider surface: `anthropic-aws`, `quiverai`, `voyage`.
- Tooling/internal surface: `harness`, `harness-claude-code`,
  `harness-codex`, `harness-deepagents`, `harness-opencode`, `harness-pi`,
  `policy-opa`, `sandbox-just-bash`, `sandbox-vercel`, `tui`,
  `workflow-harness`.

Recommended audit order:
1) Re-audit P0 core contracts first: `provider`, `provider-utils`, then `ai`.
2) Audit `openai-compatible`, because it is P0 and currently only `mapped`.
3) Re-audit P0 providers by blast radius: `openai`, `anthropic`, `gateway`,
   `google`, `google-vertex`.
4) Triage missing P1 provider surface: decide whether Swift should add
   `anthropic-aws`, `voyage`, and `quiverai`, or mark them intentionally out of
   scope.
5) After P0 contracts stabilize, sweep stale P1 providers in provider-first
   vertical slices.

## How to track a provider

1) Copy `upstream/providers/_template.md` → `upstream/providers/<provider>.md`
2) Fill:
   - upstream paths under `external/vercel-ai-sdk/packages/<provider>/src/**`
   - Swift paths under `Sources/<ProviderName>Provider/**`
   - audited commit hash from `upstream/UPSTREAM.md`
3) Update the checklist as you verify behaviors (tests preferred).

## Release recap (Swift tags)

This is a lightweight “memory log” of what we shipped while chasing upstream parity.
For source-of-truth code, always follow the commits and tests.

### Unreleased (main)

- 2026-04-15
  - Anthropic upload parity on refreshed upstream `4891db8bfc583d3767831dac83439ac190c93cb0`: added provider-side `files()` / `skills()` surfaces with multipart upload support (`AnthropicFiles`, `AnthropicSkills`), including `files-api-2025-04-14` / `skills-2025-10-02` beta headers, version-metadata fetch for uploaded skills, and direct regression coverage for multipart payloads plus mapped provider metadata.
  - Core upload parity on refreshed upstream `4891db8bfc583d3767831dac83439ac190c93cb0`: added `AISDKProvider` v4 files/skills contracts and AI-level `uploadFile` / `uploadSkill` helpers with media-type auto-detection, provider capability checks, and direct regression coverage for provider passthrough plus unsupported-provider / URL-input errors.

- 2026-03-31
  - Amazon Bedrock parity on refreshed upstream `b0c59e850b3d51db40a0816c562da52c63ceaba2`: `convertToBedrockChatMessages` now preserves assistant reasoning parts without Bedrock metadata and no longer trims reasoning text when a Bedrock signature is present; added direct regression coverage for both cases.

- 2026-03-21
  - Anthropic parity on refreshed upstream `a921fbb381cf2d19ef75ae27906f8d1cb0b8325b`: added Swift support for provider tools `code_execution_20260120`, `web_fetch_20260209`, and `web_search_20260209`, extended Anthropic tool-name mapping / prepare-tools / public wrappers accordingly, and restored encrypted `code_execution` result round-tripping (`encrypted_code_execution_result`) through prompt conversion and response parsing with direct regression coverage.
  - UI message stream callback parity audit on refreshed upstream `a921fbb381cf2d19ef75ae27906f8d1cb0b8325b`: added direct Swift regressions for `createUIMessageStream` `onFinish` delivery, persistence-mode `messageId` injection/preservation, async `execute` error mapping, and post-close writes, plus `handleUIMessageStreamFinish` passthrough coverage for abort / `finish-step` chunks when no callbacks are installed.
  - UI message stream parity audit on refreshed upstream `a921fbb381cf2d19ef75ae27906f8d1cb0b8325b`: confirmed the previously landed `v0.12.0` UI stream work is already present in Swift (`finishReason`, `abort.reason`, tool `title` / `providerMetadata`, and static/dynamic `output-denied` state handling), and added direct regressions for tool-input metadata/title retention plus static/dynamic denial transitions in `ProcessUIMessageStreamTests.swift` and `UIMessageChunkTests.swift`.
  - Core programmatic tool-calling parity on refreshed upstream `a921fbb381cf2d19ef75ae27906f8d1cb0b8325b`: strengthened the `generateText` / `streamText` multi-step dice game regressions to assert final `response.messages`, deferred `toolResults`, and `onStepFinish` / `onFinish` callback contracts for provider-deferred `code_execution` flows, matching the upstream `programmatic tool calling` fixture more closely.
  - Core deferred tool-result parity on refreshed upstream `a921fbb381cf2d19ef75ae27906f8d1cb0b8325b`: `generateText` and `streamText` now preserve provider `tool-result` / `tool-error` `providerMetadata` like upstream, and `streamText` now keeps the original static-vs-dynamic typed result kind from the matched tool call when provider results arrive; updated direct deferred-result regressions accordingly.

- 2026-03-07
  - OpenAI parity on refreshed upstream `a921fbb381cf2d19ef75ae27906f8d1cb0b8325b`: synced Responses model IDs with upstream additions (`gpt-5.2-codex`, `gpt-5.4`, `gpt-5.4-pro`, dated `gpt-5.4` snapshots, `gpt-5.3-codex`), enabled GPT-5.4 non-reasoning parameter compatibility when `reasoningEffort == "none"`, preserved Responses `phase` (`commentary` / `final_answer`) across assistant follow-up input conversion plus non-streaming/streaming provider metadata, and updated OpenAI provider docs for GPT-5.4 / GPT-5.3-codex with direct Swift regressions.
  - UI file-input parity on refreshed upstream `a921fbb381cf2d19ef75ae27906f8d1cb0b8325b`: added public Swift `convertFileListToFileUIParts(files:)` as the browser-to-Swift adaptation of upstream `FileList` conversion, reading local file URLs into `FileUIPart` data URLs with MIME-type inference plus `application/octet-stream` fallback; added direct regressions for `nil`, text-file conversion, unknown-type fallback, and non-file URL rejection.
  - UI text stream parity on refreshed upstream `a921fbb381cf2d19ef75ae27906f8d1cb0b8325b`: added public Swift `processTextStream(stream:onTextPart:)` with incremental UTF-8 decoding across chunk boundaries, matching upstream chunk callback behavior for regular, empty, and split-multibyte text streams; added direct regressions for plain chunk delivery, empty streams, and UTF-8 boundary preservation.
  - UI stream error parity on refreshed upstream `a921fbb381cf2d19ef75ae27906f8d1cb0b8325b`: promoted `UIMessageStreamError` to a public Swift `AISDKError` with stable `chunkType`/`chunkId`, restored typed error propagation for malformed UI streams through both `processUIMessageStream` and `readUIMessageStream`, and kept `.error` chunks as generic message errors like upstream; added typed regressions for malformed text/tool chunks plus a `readUIMessageStream` terminate-on-error smoke test.
  - UI message helper parity on refreshed upstream `a921fbb381cf2d19ef75ae27906f8d1cb0b8325b`: added missing exported helper guards `isTextUIPart`, `isFileUIPart`, and `isReasoningUIPart` with direct Swift regressions.
  - UI message helper parity on refreshed upstream `a921fbb381cf2d19ef75ae27906f8d1cb0b8325b`: added public Swift helpers `lastAssistantMessageIsCompleteWithToolCalls(...)` and `lastAssistantMessageIsCompleteWithApprovalResponses(...)`, restored upstream-style tool/data helper surface in `UIMessage` (`isDataUIPart`, `isToolUIPart`, `isStaticToolUIPart`, `getToolName`, `getStaticToolName`), and added direct regression coverage for static/dynamic tool names, type guards, provider-executed exclusions, and approval/tool-call completion checks.
  - UI validation parity on refreshed upstream `a921fbb381cf2d19ef75ae27906f8d1cb0b8325b`: `validateUIMessages` now rejects empty message arrays and empty `parts` arrays with upstream message text, and `TypeValidationError` now preserves human-readable local validation messages for these cases; added direct regression coverage for both non-empty contract failures.
  - UI stream invariant parity on refreshed upstream `a921fbb381cf2d19ef75ae27906f8d1cb0b8325b`: `processUIMessageStream` now throws descriptive errors for malformed `text-*`, `reasoning-*`, and `tool-input-delta` sequences without their corresponding start chunks, and now resolves `tool-output-*` / approval / denied updates from the already-existing tool invocation type instead of trusting mismatched `dynamic` flags; added direct Swift regressions for malformed stream errors and static-tool output updates under dynamic-flag mismatch.
  - UI parity on refreshed upstream `a921fbb381cf2d19ef75ae27906f8d1cb0b8325b`: `convertToModelMessages` now preserves `tool-approval-response` for provider-executed static tools (while still avoiding duplicate tool results in `tool` role), and `processUIMessageStream` now keeps the original static-vs-dynamic tool part kind when `tool-input-error` arrives with a mismatched `dynamic` flag; added direct Swift regressions for both cases.
  - UI convert-to-model parity on refreshed upstream `a921fbb381cf2d19ef75ae27906f8d1cb0b8325b`: `convertToModelMessages` now treats dynamic tools like upstream in assistant/tool message conversion, including provider-executed dynamic tool results staying in assistant content, client-executed tool-message `tool-result` parts carrying `callProviderMetadata` as provider options, and `tool-approval-response` forwarding `providerExecuted`; added direct Swift regression coverage for static/dynamic tool result and approval-response cases.
  - UI message stream / UI message parity on refreshed upstream `a921fbb381cf2d19ef75ae27906f8d1cb0b8325b`: added `resultProviderMetadata` flow for tool output chunks and UI tool parts, propagated metadata through `transformFullToUIMessageStream` → chunk encoding → `processUIMessageStream` → `validateUIMessages` → `convertToModelMessages`, and added direct Swift regression coverage for static/dynamic tool outputs plus provider-executed tool result round-tripping.
  - UI message stream: restored upstream API parity for `createUIMessageStream(...)` by exposing `onStepFinish` and forwarding it into `handleUIMessageStreamFinish`; added direct Swift regression coverage for write/close, merged-stream error mapping, delayed merged streams after `execute` returns, and `onStepFinish` callback delivery.

- 2026-02-26
  - Fireworks: provider auth parity fix — removed creation-time `fatalError` for missing API key; auth now resolves at request time (`LoadAPIKeyError`) via fetch wrapper; added upstream alias parity (`createFireworks`) and regression coverage for no-network-before-fail semantics.
  - Luma: provider auth parity fix — removed creation-time `fatalError` for missing API key; auth now resolves at request time (`LoadAPIKeyError`) via fetch wrapper; added upstream alias parity (`createLuma`) and regression coverage for no-network-before-fail semantics.
  - Hume: provider auth parity fix — removed creation-time `fatalError` for missing API key; auth now resolves at request time (`LoadAPIKeyError`) via fetch wrapper; added regression coverage for no-network-before-fail semantics.
  - Hugging Face: provider auth parity fix — removed creation-time `fatalError` for missing API key; auth now resolves at request time (`LoadAPIKeyError`) via fetch wrapper; added upstream alias parity (`createHuggingFace`) and regression coverage for no-network-before-fail semantics.
  - Gladia: provider auth parity fix — removed creation-time `fatalError` for missing API key; auth now resolves at request time (`LoadAPIKeyError`) via fetch wrapper; added upstream alias parity (`createGladia`) and regression coverage for no-network-before-fail semantics.
  - ElevenLabs: provider auth parity fix — removed creation-time `fatalError` for missing API key; auth now resolves at request time (`LoadAPIKeyError`) via fetch wrapper; added upstream alias parity (`createElevenLabs`) and regression coverage for no-network-before-fail semantics.
  - Deepgram: provider auth parity fix — removed creation-time `fatalError` for missing API key; auth now resolves at request time (`LoadAPIKeyError`) via fetch wrapper; added upstream alias parity (`createDeepgram`) and regression coverage for no-network-before-fail semantics.
  - Azure OpenAI: provider auth/config parity fix — removed creation-time `fatalError` for missing API key/resource name; validation now happens at request time (`LoadAPIKeyError` / `LoadSettingError`) via auth fetch wrapper; added regression coverage for no-network-before-fail semantics.
  - LMNT: provider auth parity fix — removed creation-time `fatalError` for missing API key; auth now resolves at request time (`LoadAPIKeyError`) via fetch wrapper; added speech-model regression coverage for missing key behavior and no-network-before-fail semantics.
  - Fal: provider auth parity fix — removed creation-time `fatalError` for missing API key; auth now resolves at request time (`LoadAPIKeyError`) via fetch wrapper; added provider regression coverage for missing key behavior and no-network-before-fail semantics.
  - Replicate: provider auth parity fix — removed creation-time `fatalError` for missing API token; auth now resolves at request time (`LoadAPIKeyError`) via fetch wrapper; added provider regression coverage for missing token behavior and no-network-before-fail semantics.
  - Prodia: provider auth parity fix — removed creation-time `fatalError` for missing API key; auth now resolves at request time (`LoadAPIKeyError`) via fetch wrapper; added provider regression coverage for missing key behavior and no-network-before-fail semantics.
  - Black Forest Labs: provider auth parity fix — removed creation-time `fatalError` for missing API key; auth now resolves at request time (`LoadAPIKeyError`) via fetch wrapper; added provider regression coverage for missing key behavior and no-network-before-fail semantics.
  - Rev.ai: provider auth parity fix — removed creation-time `fatalError` for missing API key; auth now resolves at request time (`LoadAPIKeyError`) via fetch wrapper; added regression coverage in `RevAIProviderAuthTests`.
  - Cerebras: provider auth parity fix — removed creation-time `fatalError` for missing API key; auth now resolves at request time (`LoadAPIKeyError`) via fetch wrapper, with added provider regression coverage for missing key behavior.
  - AssemblyAI: provider parity fix — removed creation-time `fatalError` for missing API key; auth now resolves at request time (`LoadAPIKeyError`) via fetch wrapper, added upstream alias `createAssemblyAI(...)`, and added provider regression tests (alias + endpoint flow + missing key).
  - DeepInfra: provider parity fix — removed creation-time `fatalError` for missing API key; auth now resolves at request time (`LoadAPIKeyError`) via fetch wrapper, added upstream alias `createDeepInfra(...)`, and added provider regression tests (alias + default chat base URL + missing key).
  - Cohere: provider parity fix — removed creation-time `fatalError` for missing API key; auth now resolves at request time (`LoadAPIKeyError`) via fetch wrapper, added upstream alias `createCohere(...)`, and added provider regression tests (alias + default base URL + missing key).
  - Perplexity: provider parity fix — removed creation-time `fatalError` for missing API key; auth now resolves at request time (`LoadAPIKeyError`) via fetch wrapper, added upstream alias `createPerplexity(...)`, and added provider regression tests (alias + default base URL + missing key).
  - Mistral: provider auth parity fix — API key now loads at request time via auth fetch wrapper, missing key throws `LoadAPIKeyError` instead of crashing; added upstream alias `createMistral(...)` and provider-level regression tests.
  - Groq: provider auth parity fix — API key now loads at request time via auth fetch wrapper, missing key throws `LoadAPIKeyError` instead of crashing; added `createGroq(...)` alias for upstream API parity and provider-level regression tests.
  - DeepSeek: provider auth/baseURL parity fix — default base URL aligned to upstream (`https://api.deepseek.com`), API key now loads at request time via auth fetch wrapper, and missing key throws `LoadAPIKeyError` instead of crashing; added regression tests.
  - OpenAI Responses: provider-options `include` parity tightened to upstream schema-only values (`reasoning.encrypted_content`, `file_search_call.results`, `message.output_text.logprobs`) while preserving internal auto-includes (`web_search_call.action.sources`, `code_interpreter_call.outputs`) for request mapping; added parsing regression tests.
  - TogetherAI: provider auth parity fix — API key now loads at request time via auth fetch wrapper; missing key throws `LoadAPIKeyError` instead of crashing; added provider tests for missing key + auth header injection.
  - Vercel (v0): provider auth parity fix — API key now loads at request time via auth fetch wrapper; missing key throws `LoadAPIKeyError` instead of crashing; added provider test for missing key.
  - Alibaba: port the upstream `@ai-sdk/alibaba` provider (Qwen chat + Wan video generation) including thinking mode, prompt caching (`cacheControl`), tool calling + streaming SSE mapping, and video polling, with end-to-end Swift tests.
  - xAI: add upstream parity for `grok-imagine-video` (generations/edits request mapping, polling behavior, edit-mode warnings, headers/metadata) with Swift tests.
  - xAI: add upstream parity for Responses API (`/responses`) + server-side tools, replace image generation with dedicated `XAIImageModel` (URL download behavior + provider options + metadata), and load API key lazily with request-time `LoadAPIKeyError` (no `fatalError`) + tests.
  - Amazon Bedrock: embedding + image model parity (Cohere/Nova/Titan embeddings; Nova Canvas image gen/editing) + SigV4 fetch coverage, strict response validation, `encodeURIComponent` URL parity, and provider-level tests.
  - xAI: align chat/completions parity (request mapping, usage conversion incl cached+reasoning tokens, and streaming JSON error handling/block ordering) + tests.

- 2026-02-25
  - Anthropic: auth header parity and error semantics now match upstream behavior more closely: API key is loaded lazily and missing key throws request-time `LoadAPIKeyError` (no `fatalError`); `apiKey`/`authToken` conflict now throws `InvalidArgumentError` (no crash). Added coverage in `AnthropicProviderAuthErrorTests`.
  - OpenAI-compatible: request mapping parity updates (provider options, structured outputs strictness, usage passthrough) and new Moonshot AI provider built on OpenAI-compatible with mapping/tests.
  - Open Responses: port the upstream `open-responses` package (request mapping, response/stream decoding, tools/usage) with end-to-end tests.
  - Google/Vertex Gemini image parity: when `usageMetadata` is missing, image generation now still returns usage object with `totalTokens = 0` (matching upstream conversion path); added regression coverage in `GoogleGenerativeAIImageModelTests` and `GoogleVertexImageModelTests`.
  - Google/Vertex Gemini image parity: add regression coverage for Gemini-only aspect ratio `21:9` being forwarded into `generationConfig.imageConfig.aspectRatio`.
  - Google provider parity: align `supportedUrls` files regex construction to upstream unescaped `baseURL` interpolation; add regression coverage in `GoogleProviderTests`.
  - Google/Vertex video parity coverage: add regression tests for alternative model IDs, `n -> sampleCount`, multi-video decode, and empty warnings defaults in `GoogleGenerativeAIVideoModelTests` and `GoogleVertexVideoModelTests`.
  - Google language parity coverage: add regression tests for code-execution finishReason semantics (`providerExecuted` tools keep `STOP -> stop`, mixed function calls keep `STOP -> tool-calls`) and stream mapping of missing `codeExecutionResult.output` to empty string in `GoogleGenerativeAILanguageModelParityTests`.
  - Google language parity: `inlineData` file parts now preserve thought-signature metadata via `providerMetadata` in generate output (stream remains metadata-free, as upstream); added regression coverage in `GoogleGenerativeAILanguageModelTests` and `LanguageModelV3ContentTests`.
  - Google language request-shape parity: explicitly empty `thinkingConfig`/`imageConfig` provider option objects are forwarded as empty objects in `generationConfig` (matches upstream); code-execution tool-call/result no longer attach thought-signature metadata directly.
  - Google language parity: invalid stream chunk schema now emits serialized validation parse error payload (`AI_TypeValidationError`/`AI_JSONParseError` fields) instead of raw chunk JSON.
  - Google tools schema parity: `convertJSONSchemaToOpenAPISchema` now matches upstream for nested empty object schemas (root removed; nested preserved) and for `type: [...]` arrays (converted to `anyOf` + `nullable`), with upstream tests ported to Swift.
  - Google Vertex provider config: custom `baseURL` bypasses `project/location` validation when `apiKey` is absent; missing config errors remain request-time (tests updated accordingly).
  - Google Vertex auth parity (Vertex mode): when `apiKey` is absent and `baseURL` is not provided, requests now auto-inject `Authorization: Bearer <token>` via service-account credentials (settings or env), matching upstream Node/Edge wrapper behavior; added regression coverage in `GoogleVertexAuthTests`.
  - SwiftAISDK tests: stabilized `RerankTests.logsWarnings` against parallel observer races by capturing non-empty warning batches instead of last write wins.

- 2026-02-24
  - Google Vertex: embedding options parity fix — `outputDimensionality` now accepts fractional numbers and rejects `null` (Vertex + Google fallback namespaces), with new coverage in `GoogleVertexEmbeddingModelTests`.
  - Google: language provider options parity fix — `null` is now rejected for optional schema fields (including nested `thinkingConfig.includeThoughts`), with regression coverage in `GoogleGenerativeAILanguageModelTests`.
  - Google/Vertex Imagen: preserve explicit `null` for nullish image provider options in request `parameters`; Google Imagen now defaults missing `predictions` to an empty array (upstream response schema parity).
  - Google streaming: align chunk parsing with upstream by accepting usage-only chunks without `candidates` (no false parse-error events), with regression coverage in `GoogleGenerativeAILanguageModelTests`.

- 2026-02-23
  - Anthropic: Claude 4.6 support (thanks to @bunchjesse).
  - Google Vertex: custom `baseURL` now bypasses `project/location` requirement when explicitly configured (regression test added).
  - OpenAI: upstream parity fixes for Responses provider tools:
    - `web_search_call` now maps to upstream output contract (`action` + optional `sources`) in non-stream + stream.
    - `local_shell_call` input mapping now matches upstream snake_case contract (`timeout_ms`, `working_directory`) in non-stream + stream.
    - `mcp_approval_request` no longer emits extra tool-call provider metadata (matches upstream output shape).
    - `shell` assistant tool-results with `store=true` are reconstructed as `shell_call_output` (instead of `item_reference`) like upstream.
    - `web_search` / `web_search_preview` schema strictness aligned with upstream (`userLocation.type` required, discriminated output actions).
    - Missing OpenAI API key now throws request-time error (lazy load) instead of `fatalError`.
    - Completion parity: `logprobs` mapping (`true -> 0`, `false -> omitted`), plus Responses shell/file-search/image parity updates and tests.

- 2026-02-04
  - Breaking: align `LanguageModelV3FinishReason` with upstream as `{ unified, raw }` and propagate raw finish reasons through providers + `generateText`/`streamText` pipelines (tests updated).
  - Anthropic: tool results no longer set `providerExecuted` (upstream parity); MCP tool-call/result are `dynamic: true` (tests updated).
  - UI: align UI message stream chunks with upstream (`finishReason`, abort `reason`, tool `title`/`providerMetadata`, dynamic tool states) + tests.
  - Core: align `LanguageModelV3ToolResult` with upstream (remove `providerExecuted`); tool results coming from providers are treated as `providerExecuted: true` at the AI level (matches upstream `runToolsTransformation`).
  - Added: reranking model V3 + core `rerank` API parity; Cohere + Amazon Bedrock reranking providers + tests.
  - Added providers: TogetherAI (image + reranking + OpenAI-compatible chat/completion/embedding), Black Forest Labs (image w/ polling), Prodia (image w/ multipart response), Rev.ai (async transcription jobs), Vercel (v0 OpenAI-compatible chat wrapper) + tests.

- 2026-02-05
  - Core: add experimental `experimental_generateVideo` API + `VideoModelV3` (v3) types (ported from upstream `generate-video`).
  - Fal: add `FalVideoModel` + `fal.video(...)` wiring (queue polling + providerMetadata mapping) + tests.
  - Docs: add Video Generation page + Fal provider page (incl. video models) and wire both into the sidebar.

- 2026-02-06
  - Fal: close non-video parity for image/speech/transcription against pinned baseline `f3a72bc2` (request mapping, error mapping, metadata mapping, polling behavior).
  - Fal: add provider/model parity coverage in `Tests/FalProviderTests/FalProviderTests.swift`, `Tests/FalProviderTests/FalImageModelTests.swift`, `Tests/FalProviderTests/FalSpeechModelTests.swift`, `Tests/FalProviderTests/FalTranscriptionModelTests.swift`, `Tests/FalProviderTests/FalErrorTests.swift`.
  - Provider utils: extend `JSONSchemaValidator` to validate tuple schemas (`items: [...]` + `additionalItems`), `uniqueItems`, `multipleOf`, object property count constraints, string `format`/`contentEncoding`, and ensure `anyOf`/`oneOf` doesn't bypass base keywords + tests.
  - Core: fix `AsyncIterableStream` init race that could leave streams open/hanging + regression test.
  - Tools: harden `tools/test-runner.js` (selectors + Swift Testing output parsing) and add `tools/test-suspicious.config.json` for UI message stream suites.

### v0.7.x

- `v0.7.0` (2026-01-26)
  - Core: tool approval requests + dynamic tools.
  - SwiftAISDK: handle approvals in `generate/stream`.
  - OpenAI: Responses MCP tool support + docs/tests for approvals.
- `v0.7.1` (2026-01-31)
  - OpenAI: fallback `itemId` from `providerMetadata`.
- `v0.7.2` (2026-01-31)
  - Provider: add `providerMetadata` to V3 tool parts.
  - OpenAI: Responses tool name mapping parity.
- `v0.7.3` (2026-01-31)
  - OpenAI Responses: citations/annotations `providerMetadata` parity + tests.
- `v0.7.4` (2026-02-01)
  - Release housekeeping.
- `v0.7.5` (2026-02-01)
  - Docs: README update for `0.7.4`.
- `v0.7.6` (2026-02-01)
  - OpenAI Chat: validate `logitBias` keys.
- `v0.7.77` (2026-02-01)
  - OpenAI tools: add output schemas for `web_search` tools.

### v0.8.x

- `v0.8.0` (2026-02-01)
  - Provider utils: strengthen JSON schema validation.
- `v0.8.2` (2026-02-02)
  - SSE streaming: make tool events JSON-serializable.
  - Tools: propagate tool titles through calls/results/errors and stream parts.
  - Docs/site: add branding logos + favicon.
- `v0.8.3` (2026-02-02)
  - Google: send tools as array for `functionDeclarations` (Gemini/GCP compatibility).
  - OpenAI Responses: reasoning summary streaming parity; truncation/finishReason parity.
  - Image: edits support; response_format prefix parity; remove compat init.
  - `streamText`: raw finish reason + abort reason parity.
- `v0.8.4` (2026-02-02)
  - Anthropic: code_execution/memory betas + `toolNameMapping` parity.
  - OpenAI Responses: truncation + finishReason parity.
- `v0.8.5` (2026-02-02)
  - Anthropic: tool streaming + structured outputs + metadata alignment.

### v0.9.x

- `v0.9.0` (2026-02-03)
  - Breaking: rename “provider-defined tools” → “provider tools” (upstream parity).
  - Tools: support `inputExamples` + middleware injection; stabilize JSON formatting.
  - `streamText`: apply `prepareStep` for multi-step streaming.
  - Core: unify V3 warnings under `SharedV3Warning`; `prepareStep` supports providerOptions/experimentalContext.
  - Anthropic: validate `cache_control`; forward container id between steps.
  - Docs: simplify README marketing copy.
- `v0.9.1` (2026-02-03)
  - Anthropic: align settings + custom provider option keys; align provider tool args + prepareTools.

### v0.10.x

- `v0.10.0` (2026-02-03)
  - Breaking (Anthropic): align web tool outputs with upstream.

### v0.11.x

- `v0.11.0` (2026-02-04)
  - Breaking: align `LanguageModelV3Usage` to upstream token detail shape (`inputTokens` / `outputTokens`) and update provider usage mapping accordingly.
  - SwiftAISDK: add AI-level `LanguageModelUsage` helpers + adapter from provider usage for parity with upstream `@ai-sdk/ai`.
- `v0.11.1` (2026-03-21)
  - Core: support deferred results for provider-executed tools (`supportsDeferredResults`) in `generateText`/`streamText` multi-step loops (upstream parity).
  - Streaming: map provider tool outputs with `isError: true` to `.toolError` (not `.toolResult`); propagate tool-call `providerMetadata` to executed tool results/errors (`executeToolCall` parity); preserve `providerMetadata` from provider tool-result chunks in `generateText`/`streamText` content (matches upstream).
  - Tests: add coverage for deferred provider tool results and tool providerMetadata in `Tests/SwiftAISDKTests/GenerateText/*DeferredToolResultsTests.swift`, `ExecuteToolCallProviderMetadataTests.swift`, `StreamTextToolErrorProviderMetadataTests.swift`.
  - Tests: port programmatic tool calling multi-step dice game fixture to validate provider-deferred results + client tool execution, including final `response.messages`, deferred `toolResults`, and `onStepFinish` / `onFinish` callback contracts:
    - `Tests/SwiftAISDKTests/GenerateText/GenerateTextProgrammaticToolCallingTests.swift`
    - `Tests/SwiftAISDKTests/GenerateText/StreamTextProgrammaticToolCallingTests.swift`
