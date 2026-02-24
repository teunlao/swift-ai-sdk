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
- [x] Grounding source extraction parity: maps `web` + `retrievedContext` (HTTP URL, file URI, `fileSearchStore`) + `maps` chunks to V3 `source` content (including document media-type/filename/title defaults) in generate responses, with stream coverage for map URL sources.
- [x] Warnings parity: `includeThoughts` on non-Vertex providers does not emit warning; `google.vertex_rag_store` on non-Vertex providers emits upstream-compatible provider warning.
- [x] Request shape parity for explicit empty inputs: preserve empty `stopSequences`, empty `responseModalities`, empty `safetySettings`, and empty `labels` when explicitly provided.
- [x] Thought signature parity for assistant files: preserve `providerOptions.*.thoughtSignature` on assistant `file` parts and encode it as part-level `thoughtSignature` alongside `inlineData`.
- [x] Stream parse-error payload parity: when an SSE chunk fails schema parsing, emit structured JSON error payload (prefer raw parsed chunk) instead of stringifying the error object only.

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
