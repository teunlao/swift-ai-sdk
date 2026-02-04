# Provider: Google Vertex

- Audited against upstream commit: `f5b2b5ef497ae6c207c17bb8ff81988ef084194b`
- Upstream package: `external/vercel-ai-sdk/packages/google-vertex/src/**`
- Swift implementation: `Sources/GoogleVertexProvider/**`

## What is verified (checked + tested)

- [x] Express mode support: `apiKey` / `GOOGLE_VERTEX_API_KEY` uses base URL `https://aiplatform.googleapis.com/v1/publishers/google`.
- [x] Express mode auth: always sets and overrides `x-goog-api-key` header (even if caller passes a different value).
- [x] Chat model baseURL: regional host prefix + global region handling + express mode base URL; express mode injects `x-goog-api-key` (generate + stream).
- [x] Embedding provider options: reads options from `providerOptions["vertex"]` (fallback to `providerOptions["google"]`).
- [x] Embedding model: request payload (`instances`/`parameters`), usage tokens, raw response headers/body, custom `baseURL`, custom `fetch`, too-many-values guard.
- [x] Image model (doGenerate): request payload (aspectRatio/seed/sampleCount), warnings for unsupported `size`, provider option filtering, providerMetadata (revised prompts), response timestamp/headers.
- [x] Image editing mode (files/mask): builds `referenceImages` payload, supports `providerOptions.vertex.edit.*`, rejects URL-based images (upstream parity).
- [x] Error mapping (Vertex): non-2xx responses throw `APICallError` with `error.message` for embedding + image calls.
- [x] Tool factories: `googleVertexTools` exposes the same provider-defined tools surface as upstream (`google_search`, `url_context`, `code_execution`, plus `enterprise_web_search`, `google_maps`, `file_search`, `vertex_rag_store`).

Tests live under:
- `Tests/GoogleVertexProviderTests/GoogleVertexChatBaseURLTests.swift`
- `Tests/GoogleVertexProviderTests/GoogleVertexChatStreamingBaseURLTests.swift`
- `Tests/GoogleVertexProviderTests/GoogleVertexProviderExpressModeTests.swift`
- `Tests/GoogleVertexProviderTests/GoogleVertexEmbeddingModelTests.swift`
- `Tests/GoogleVertexProviderTests/GoogleVertexImageEditingTests.swift`
- `Tests/GoogleVertexProviderTests/GoogleVertexImageModelTests.swift`
- `Tests/GoogleVertexProviderTests/GoogleVertexErrorHandlingTests.swift`

## Known gaps / TODO

- [ ] Full end-to-end parity audit (prompt conversion, streaming, errors) for `google-vertex`.

## Notes

- Upstream (key files):
  - `external/vercel-ai-sdk/packages/google-vertex/src/google-vertex-provider.ts`
  - `external/vercel-ai-sdk/packages/google-vertex/src/google-vertex-tools.ts`
- Swift (key files):
  - `Sources/GoogleVertexProvider/GoogleVertexProvider.swift`
  - `Sources/GoogleVertexProvider/GoogleVertexTools.swift`
