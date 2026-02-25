# Provider: Google

- Audited against upstream commit: `73d5c5920e0fea7633027fdd87374adc9ba49743`
- Upstream package: `external/vercel-ai-sdk/packages/google/src/**`
- Swift implementation: `Sources/GoogleProvider/**`

## What is verified (checked + tested)

- [x] Tools request payload shape: tools are encoded as an array under `functionDeclarations` (Gemini-compatible).
- [x] Provider tools: prepareTools mapping for `google_search`, `url_context`, `code_execution`, `enterprise_web_search`, `file_search`, `vertex_rag_store`, `google_maps` (model gating + payload shapes).
- [x] Provider tool factories: tool ids/names and args schemas for the provider-defined tools listed above.
- [x] Missing `GOOGLE_GENERATIVE_AI_API_KEY` now throws `LoadAPIKeyError` at request-time (no process crash / no `fatalError`).
- [x] Google error payload schema parity: `error.code` is required (nullable); malformed error payloads now fall back to status-text `APICallError`.
- [x] Embedding provider options parity: `outputDimensionality` accepts any numeric value (not only integers).
- [x] Embedding request mapping parity: `model` field in single + batch embed requests always uses `models/<modelId>` (including model IDs containing `/`).
- [x] Supported file URL parity: Google Files/YouTube URL checks are case-sensitive (no implicit lowercasing/case-insensitive regex).
- [x] Supported file URL regex construction parity: files endpoint regex interpolates `baseURL` directly (unescaped), matching upstream dynamic-regex semantics.
- [x] Grounding source extraction parity: maps `web` + `retrievedContext` (HTTP URL, file URI, `fileSearchStore`) + `maps` chunks to V3 `source` content (including document media-type/filename/title defaults) in generate responses, with stream coverage for map URL sources.
- [x] Warnings parity: `includeThoughts` on non-Vertex providers does not emit warning; `google.vertex_rag_store` on non-Vertex providers emits upstream-compatible provider warning.
- [x] Request shape parity for explicit empty inputs: preserve empty `stopSequences`, empty `responseModalities`, empty `safetySettings`, and empty `labels` when explicitly provided.
- [x] Provider options validation parity: `null` is rejected for optional Google language options (e.g. `responseModalities`, nested `thinkingConfig.includeThoughts`) to match upstream schema behavior.
- [x] Thought signature parity for assistant files: preserve `providerOptions.*.thoughtSignature` on assistant `file` parts and encode it as part-level `thoughtSignature` alongside `inlineData`.
- [x] Stream parse-error payload parity: when an SSE chunk fails schema parsing, emit structured JSON error payload (prefer raw parsed chunk) instead of stringifying the error object only.
- [x] Stream chunk schema parity: chunks without `candidates` are accepted (usage/metadata-only chunks) instead of being treated as parse errors.
- [x] Tool schema conversion parity: `convertJSONSchemaToOpenAPISchema` matches upstream for nested empty object schemas (root is removed; nested schemas are preserved) and for `type: [...]` arrays (converted to `anyOf` + `nullable`).
- [x] Imagen request-shape parity: explicit `null` for nullish image provider options (`personGeneration`, `aspectRatio`) is preserved in `parameters` and can override defaults (upstream `Object.assign` behavior).
- [x] Imagen response-schema parity: missing `predictions` defaults to `[]` instead of failing decode.
- [x] Gemini image usage parity: missing `usageMetadata` still maps to a usage object with `totalTokens = 0` (instead of omitting usage entirely), matching upstream usage conversion flow.
- [x] Gemini image aspect-ratio parity: Gemini-only ratios such as `21:9` are forwarded via `generationConfig.imageConfig.aspectRatio`.
- [x] Video model parity coverage: supports alternative model IDs, maps `n` to `sampleCount`, returns multiple videos, and returns an empty warnings array when no warnings are produced.
- [x] Code execution finish-reason parity: provider-executed `code_execution` yields `stop` (not `tool-calls`) unless a client function call is present; stream coverage includes missing `codeExecutionResult.output` mapping to empty string.
- [x] File content metadata parity: `inlineData` parts in generate responses carry `providerMetadata` (thought signature), while streamed `file` chunks intentionally omit it, matching upstream behavior.
- [x] Stream parse-error payload parity: invalid SSE chunk schema now emits serialized parse/type-validation error payload (`name`/`message`/`value`) instead of raw chunk JSON.

## Known gaps / TODO

- [ ] Full end-to-end parity audit (prompt conversion, streaming, errors) — not yet fully checked for `google`.

## Notes

- Fix shipped in `v0.8.3`: `fix(google): send tools as array for functionDeclarations`
- `google-vertex` progress is tracked separately in `upstream/providers/google-vertex.md`.
- Related Swift files:
  - `Sources/GoogleProvider/GooglePrepareTools.swift`
  - `Sources/GoogleProvider/GoogleTools.swift`
  - `Sources/GoogleProvider/Tool/*`
  - `Tests/GoogleProviderTests/GooglePrepareToolsTests.swift`
