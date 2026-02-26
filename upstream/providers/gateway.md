# Provider: Gateway (Vercel AI Gateway)

- Audited against upstream commit: `73d5c5920e0fea7633027fdd87374adc9ba49743`
- Upstream package: `external/vercel-ai-sdk/packages/gateway/src/**`
- Swift implementation: `Sources/GatewayProvider/**`

## What is verified (checked + tested)

- [x] Gateway metadata fetcher:
  - `GET {baseURL}/config` request mapping.
  - Cache pricing field mapping (`input_cache_read`/`input_cache_write` → `cachedInputTokens`/`cacheCreationInputTokens`).
  - `modelType` validation rejects invalid values (must be one of `language|embedding|image|video` when present).
- [x] Credits fetcher:
  - `GET {origin}/v1/credits` request mapping (origin derived from `baseURL`).
  - Response mapping (`total_used` → `totalUsed`).
- [x] Language model:
  - `POST {baseURL}/language-model` request mapping (headers + body) and abort-signal stripping.
  - File part encoding: binary `file` parts become `data:<mime>;base64,...` URLs in request body.
  - Streaming: raw chunks are filtered unless `includeRawChunks=true`; `response-metadata.timestamp` ISO strings are parsed into `Date`.
- [x] Embedding model:
  - `POST {baseURL}/embedding-model` request mapping (`values` array + optional `providerOptions`).
  - Headers: `ai-embedding-model-specification-version=3` and `ai-model-id` set.
  - Response mapping: embeddings + usage + `providerMetadata` passthrough; Gateway error responses map to typed Gateway errors.
- [x] Image model:
  - `POST {baseURL}/image-model` request mapping (headers + body, optional params omitted when `nil`).
  - File encoding: binary `ImageModelV3File` is sent as base64 strings; providerOptions on files/mask are preserved.
  - Response mapping: base64 images + warnings + usage; `providerMetadata` is converted into `ImageModelV3ProviderMetadataValue` (missing `images` becomes `[]`).
- [x] Video model:
  - `POST {baseURL}/video-model` request mapping (headers + body, `accept=text/event-stream`).
  - Video results are parsed from the first SSE `data:` event (`type=result`); SSE `type=error` events map to typed Gateway errors.
  - Image-to-video file encoding: binary `VideoModelV3File` is sent as base64 strings; providerOptions on the image are preserved.
  - Response mapping: videos + warnings + `providerMetadata` passthrough.
- [x] Provider creation:
  - Default `baseURL` is `https://ai-gateway.vercel.sh/v3/ai` (upstream parity).
- [x] Gateway provider-defined tools:
  - `gateway.tools.parallelSearch(...)` (`id=gateway.parallel_search`) args mapping + input/output schemas.
  - `gateway.tools.perplexitySearch(...)` (`id=gateway.perplexity_search`) args mapping + input/output schemas.
- [x] `asGatewayError` parity (timeout detection):
  - Undici timeout error codes (`UND_ERR_*_TIMEOUT`) and `URLError.timedOut` map to `GatewayTimeoutError`.
  - `APICallError` with a timeout cause maps to `GatewayTimeoutError` (with helpful message).

Tests live under:
- `Tests/GatewayProviderTests/GatewayFetchMetadataTests.swift`
- `Tests/GatewayProviderTests/GatewayLanguageModelTests.swift`
- `Tests/GatewayProviderTests/GatewayEmbeddingModelTests.swift`
- `Tests/GatewayProviderTests/GatewayImageModelTests.swift`
- `Tests/GatewayProviderTests/GatewayVideoModelTests.swift`
- `Tests/GatewayProviderTests/GatewayProviderCreationTests.swift`
- `Tests/GatewayProviderTests/GatewayToolsTests.swift`
- `Tests/GatewayProviderTests/AsGatewayErrorTests.swift`

## Known gaps / TODO

- [ ] Error mapping parity for all Gateway error shapes/status codes (e.g. generationId passthrough, less-common response shapes).
- [ ] Vercel environment parity (`vercel-environment.ts`) and provider options parsing.

## Notes

- Upstream (key files):
  - `external/vercel-ai-sdk/packages/gateway/src/gateway-fetch-metadata.ts`
  - `external/vercel-ai-sdk/packages/gateway/src/gateway-model-entry.ts`
- Swift (key files):
  - `Sources/GatewayProvider/GatewayFetchMetadata.swift`
  - `Sources/GatewayProvider/GatewayModelEntry.swift`
