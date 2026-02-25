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

- 2026-02-25
  - Anthropic: auth header parity and error semantics now match upstream behavior more closely: API key is loaded lazily and missing key throws request-time `LoadAPIKeyError` (no `fatalError`); `apiKey`/`authToken` conflict now throws `InvalidArgumentError` (no crash). Added coverage in `AnthropicProviderAuthErrorTests`.
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
- `v0.11.1` (pending)
  - Core: support deferred results for provider-executed tools (`supportsDeferredResults`) in `generateText`/`streamText` multi-step loops (upstream parity).
  - Streaming: map provider tool outputs with `isError: true` to `.toolError` (not `.toolResult`); propagate tool-call `providerMetadata` to executed tool results/errors (`executeToolCall` parity); do not propagate `providerMetadata` from provider tool-result chunks (matches upstream).
  - Tests: add coverage for deferred provider tool results and tool providerMetadata in `Tests/SwiftAISDKTests/GenerateText/*DeferredToolResultsTests.swift`, `ExecuteToolCallProviderMetadataTests.swift`, `StreamTextToolErrorProviderMetadataTests.swift`.
  - Tests: port programmatic tool calling multi-step dice game fixture to validate provider-deferred results + client tool execution:
    - `Tests/SwiftAISDKTests/GenerateText/GenerateTextProgrammaticToolCallingTests.swift`
    - `Tests/SwiftAISDKTests/GenerateText/StreamTextProgrammaticToolCallingTests.swift`

### v0.12.x

- `v0.12.0` (pending)
  - UI message stream parity: add `finishReason` to `finish` chunks + `onFinish` event, add `abort.reason`, and support `title`/`providerMetadata` on `tool-input-*` chunks.
  - UI processing: track `finishReason` in `processUIMessageStream`, propagate tool `title` into `UIToolUIPart`/`UIDynamicToolUIPart`, and handle dynamic-tool approval/denied states.
  - Encoding: SSE JSON includes `finishReason` (when available) and `abort.reason`.
  - Validation/tests: update `ValidateUIMessages` and add/update tests under `Tests/SwiftAISDKTests/UIMessageStream/*` and `Tests/SwiftAISDKTests/UI/*`.
