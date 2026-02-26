# Provider: xAI

- Audited against upstream commit: `73d5c5920e0fea7633027fdd87374adc9ba49743`
- Upstream package: `external/vercel-ai-sdk/packages/xai/src/**`
- Swift implementation: `Sources/XAIProvider/**`

## What is verified (checked + tested)

- [x] Video model parity (`grok-imagine-video`): request mapping (duration/aspectRatio/resolution), edit mode (`videoUrl`), polling behavior (interval/timeout/expired), response/provider metadata and warnings.

## Known gaps / TODO

- [ ] Responses API parity (`/responses`) + server-side tools (`xai.tools.*`).
- [ ] Image model parity (Swift currently uses `OpenAICompatibleImageModel`; upstream uses a dedicated `XaiImageModel` with different request/response + download behavior).
- [ ] API key handling parity: some xAI code paths still `fatalError` on missing key; upstream throws request-time errors.

## Notes

- Upstream: `external/vercel-ai-sdk/packages/xai/src/xai-provider.ts`
- Upstream: `external/vercel-ai-sdk/packages/xai/src/xai-video-model.ts`
- Swift: `Sources/XAIProvider/XAIProvider.swift`
- Swift: `Sources/XAIProvider/XAIVideoModel.swift`
- Tests: `external/vercel-ai-sdk/packages/xai/src/xai-video-model.test.ts` → `Tests/XAIProviderTests/XAIVideoModelTests.swift`

