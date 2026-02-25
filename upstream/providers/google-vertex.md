# Provider: Google Vertex

- Audited against upstream commit: `73d5c5920e0fea7633027fdd87374adc9ba49743`
- Upstream package: `external/vercel-ai-sdk/packages/google-vertex/src/**`
- Swift implementation: `Sources/GoogleVertexProvider/**`

## What is verified (checked + tested)

- [x] Express mode support: `apiKey` / `GOOGLE_VERTEX_API_KEY` uses base URL `https://aiplatform.googleapis.com/v1/publishers/google`.
- [x] Express mode auth: always sets and overrides `x-goog-api-key` header (even if caller passes a different value).
- [x] OAuth auth parity (Vertex mode): when `apiKey` is absent and `baseURL` is not provided, the provider auto-injects `Authorization: Bearer <token>` using service-account credentials (`googleCredentials` or env `GOOGLE_CLIENT_EMAIL`/`GOOGLE_PRIVATE_KEY`/`GOOGLE_PRIVATE_KEY_ID`). User-supplied `Authorization` header is not overridden.
- [x] Chat model baseURL: regional host prefix + global region handling + express mode base URL; express mode injects `x-goog-api-key` (generate + stream).
- [x] Embedding provider options: reads options from `providerOptions["vertex"]` (fallback to `providerOptions["google"]`).
- [x] Embedding model: request payload (`instances`/`parameters`), usage tokens, raw response headers/body, custom `baseURL`, custom `fetch`, too-many-values guard.
- [x] Image model (doGenerate): request payload (aspectRatio/seed/sampleCount), warnings for unsupported `size`, provider option filtering, providerMetadata (revised prompts), response timestamp/headers.
- [x] Image editing mode (files/mask): builds `referenceImages` payload, supports `providerOptions.vertex.edit.*`, rejects URL-based images (upstream parity).
- [x] Error mapping (Vertex): non-2xx responses throw `APICallError` with `error.message` for embedding + image calls.
- [x] Tool factories: `googleVertexTools` exposes the same provider-defined tools surface as upstream (`google_search`, `url_context`, `code_execution`, plus `enterprise_web_search`, `google_maps`, `file_search`, `vertex_rag_store`).
- [x] Missing Vertex config (`GOOGLE_VERTEX_LOCATION`/`GOOGLE_VERTEX_PROJECT`) throws `LoadSettingError` at request-time when `apiKey` is absent and `baseURL` is not provided (no process crash / no `fatalError`).
- [x] Facade aliases parity: `createVertex(...)` and default `vertex` instance are exported alongside Swift-native `createGoogleVertex` / `googleVertex`.
- [x] Version alias parity: `VERSION` is exported as an alias to `GOOGLE_VERTEX_VERSION`.
- [x] Supported URL regex parity: HTTP/GCS patterns are case-sensitive (no `.caseInsensitive` matching), with dedicated `supportedUrls` coverage.
- [x] Video request mapping parity: image payload now always includes `mimeType` (including empty string), matching upstream request body shape.
- [x] Custom base URL behavior: when `baseURL` is provided, `project/location` are not required (even when `apiKey` is absent).
- [x] Embedding options naming parity: upstream aliases `GoogleVertexEmbeddingModelOptions` / `googleVertexEmbeddingModelOptionsSchema` are exported alongside existing Swift names.
- [x] Embedding options validation parity: `outputDimensionality` accepts fractional numbers (not integer-only), and `null` for optional fields is rejected (matches upstream `.optional()` semantics for Vertex + Google fallback namespaces).
- [x] Imagen request-shape parity: explicit `null` in nullish Vertex image options (`negativePrompt`, `addWatermark`, `sampleImageSize`, etc.) is preserved in `parameters` for Imagen requests.
- [x] Gemini image usage parity: missing `usageMetadata` still maps to a usage object with `totalTokens = 0` (instead of omitting usage entirely), matching upstream usage conversion flow.
- [x] Gemini image aspect-ratio parity: Gemini-only ratios such as `21:9` are forwarded via `generationConfig.imageConfig.aspectRatio`.
- [x] Video model parity coverage: supports alternative model IDs, maps `n` to `sampleCount`, returns multiple videos, and returns an empty warnings array when no warnings are produced.

Tests live under:
- `Tests/GoogleVertexProviderTests/GoogleVertexChatBaseURLTests.swift`
- `Tests/GoogleVertexProviderTests/GoogleVertexChatStreamingBaseURLTests.swift`
- `Tests/GoogleVertexProviderTests/GoogleVertexProviderExpressModeTests.swift`
- `Tests/GoogleVertexProviderTests/GoogleVertexAuthTests.swift`
- `Tests/GoogleVertexProviderTests/GoogleVertexEmbeddingModelTests.swift`
- `Tests/GoogleVertexProviderTests/GoogleVertexImageEditingTests.swift`
- `Tests/GoogleVertexProviderTests/GoogleVertexImageModelTests.swift`
- `Tests/GoogleVertexProviderTests/GoogleVertexErrorHandlingTests.swift`

## Known gaps / TODO

- [ ] Full end-to-end parity audit (prompt conversion, streaming, errors) for `google-vertex`.

## Notes

- Intentional deviation: unlike upstream `createVertex`, Swift `createGoogleVertex` short-circuits to `baseURL` when provided (so `project/location` are not required). OAuth auto-injection is also skipped in this case (assume caller/proxy handles auth). Keep this behavior unless explicitly reverted.

- Upstream (key files):
  - `external/vercel-ai-sdk/packages/google-vertex/src/google-vertex-provider.ts`
  - `external/vercel-ai-sdk/packages/google-vertex/src/google-vertex-tools.ts`
- Swift (key files):
  - `Sources/GoogleVertexProvider/GoogleVertexProvider.swift`
  - `Sources/GoogleVertexProvider/GoogleVertexTools.swift`
