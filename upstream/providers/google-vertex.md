# Provider: Google Vertex

- Audited against upstream commit: `f5b2b5ef497ae6c207c17bb8ff81988ef084194b`
- Upstream package: `external/vercel-ai-sdk/packages/google-vertex/src/**`
- Swift implementation: `Sources/GoogleVertexProvider/**`

## What is verified (checked + tested)

- [x] Express mode support: `apiKey` / `GOOGLE_VERTEX_API_KEY` uses base URL `https://aiplatform.googleapis.com/v1/publishers/google`.
- [x] Express mode auth: always sets and overrides `x-goog-api-key` header (even if caller passes a different value).
- [x] Embedding provider options: reads options from `providerOptions["vertex"]` (fallback to `providerOptions["google"]`).
- [x] Image editing mode (files/mask): builds `referenceImages` payload, supports `providerOptions.vertex.edit.*`, rejects URL-based images (upstream parity).
- [x] Tool factories: `googleVertexTools` exposes the same provider-defined tools surface as upstream (`google_search`, `url_context`, `code_execution`, plus `enterprise_web_search`, `google_maps`, `file_search`, `vertex_rag_store`).

Tests live under:
- `Tests/GoogleVertexProviderTests/GoogleVertexProviderExpressModeTests.swift`
- `Tests/GoogleVertexProviderTests/GoogleVertexImageEditingTests.swift`

## Known gaps / TODO

- [ ] Full end-to-end parity audit (prompt conversion, streaming, errors) for `google-vertex`.

## Notes

- Upstream (key files):
  - `external/vercel-ai-sdk/packages/google-vertex/src/google-vertex-provider.ts`
  - `external/vercel-ai-sdk/packages/google-vertex/src/google-vertex-tools.ts`
- Swift (key files):
  - `Sources/GoogleVertexProvider/GoogleVertexProvider.swift`
  - `Sources/GoogleVertexProvider/GoogleVertexTools.swift`
