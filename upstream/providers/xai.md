# Provider: xAI

- Audited against upstream commit: `73d5c5920e0fea7633027fdd87374adc9ba49743`
- Upstream package: `external/vercel-ai-sdk/packages/xai/src/**`
- Swift implementation: `Sources/XAIProvider/**`

## What is verified (checked + tested)

- [x] Video model parity (`grok-imagine-video`): request mapping (duration/aspectRatio/resolution), edit mode (`videoUrl`), polling behavior (interval/timeout/expired), response/provider metadata and warnings.
- [x] Responses API parity (`/responses`) + server-side tools (`xai.tools.*`): request mapping, stream decoding, usage/finishReason mapping, and tool wiring/tests.
- [x] Image model parity: dedicated `XAIImageModel` (generations/edits), file→data URI conversion, URL download behavior, provider options (`aspect_ratio`, `output_format`, `sync_mode`), warnings, and providerMetadata mapping.
- [x] Chat language model parity (`/chat/completions`): request mapping (`max_completion_tokens`, `parallel_function_calling`, `response_format`, `search_parameters`), usage conversion (cached + reasoning tokens), 200-status `{code,error}` handling, streaming JSON-vs-SSE path + block ordering, and duplication skips + tests.
- [x] API key handling parity: API key is loaded lazily and missing key throws request-time `LoadAPIKeyError` (no `fatalError`).

## Known gaps / TODO

- [ ] None known.

## Notes

- Upstream: `external/vercel-ai-sdk/packages/xai/src/xai-provider.ts`
- Upstream: `external/vercel-ai-sdk/packages/xai/src/xai-video-model.ts`
- Upstream: `external/vercel-ai-sdk/packages/xai/src/xai-image-model.ts`
- Upstream: `external/vercel-ai-sdk/packages/xai/src/responses/xai-responses-language-model.ts`
- Swift: `Sources/XAIProvider/XAIProvider.swift`
- Swift: `Sources/XAIProvider/XAIVideoModel.swift`
- Swift: `Sources/XAIProvider/XAIImageModel.swift`
- Swift: `Sources/XAIProvider/Responses/XAIResponsesLanguageModel.swift`
- Tests: `external/vercel-ai-sdk/packages/xai/src/xai-video-model.test.ts` → `Tests/XAIProviderTests/XAIVideoModelTests.swift`
- Tests: `external/vercel-ai-sdk/packages/xai/src/xai-image-model.test.ts` → `Tests/XAIProviderTests/XAIImageModelTests.swift`
