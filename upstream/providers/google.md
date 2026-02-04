# Provider: Google

- Audited against upstream commit: `f5b2b5ef497ae6c207c17bb8ff81988ef084194b`
- Upstream package: `external/vercel-ai-sdk/packages/google/src/**`
- Swift implementation: `Sources/GoogleProvider/**`

## What is verified (checked + tested)

- [x] Tools request payload shape: tools are encoded as an array under `functionDeclarations` (Gemini-compatible).
- [x] Provider tools: prepareTools mapping for `google_search`, `url_context`, `code_execution`, `enterprise_web_search`, `file_search`, `vertex_rag_store`, `google_maps` (model gating + payload shapes).
- [x] Provider tool factories: tool ids/names and args schemas for the provider-defined tools listed above.

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
